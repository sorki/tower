{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RecordWildCards #-}

module Ivory.Tower.HAL.Bus.Sched (
  Task, task, schedule
) where

import Control.Monad (forM)
import Ivory.Language
import Ivory.Stdlib
import Ivory.Tower
import Ivory.Tower.HAL.Bus.Interface
import Ivory.Tower.HAL.Bus.Sched.Internal

-- | Multiplex a request/response bus across any number of tasks that
-- need to share it. Tasks may submit requests at any time, but only one
-- task's request will be submitted to the bus at a time. When that
-- request's response arrives, it is forwarded to the appropriate task
-- and the next waiting task's request is sent.
--
-- If multiple tasks have outstanding requests simultaneously, then this
-- component will choose the highest-priority task first. Earlier tasks
-- in the list given to 'schedule' are given higher priority.
schedule :: (IvoryArea req, IvoryZero req, IvoryArea res, IvoryZero res, IvoryArea ready, IvoryZero ready)
         => String
         -> [Task req res]
         -> ChanOutput ready
         -> BackpressureTransmit req res
         -> Tower e ()
schedule name tasks ready (BackpressureTransmit reqChan resChan) = do
  let named nm = name ++ "_scheduler_" ++ nm
  monitor (name ++ "_scheduler") $ do
    -- Task IDs are either an index into the list of tasks, or one of
    -- two special values: 'no_task' or 'not_ready_task'.
    let no_task = 0
    let min_task = 1
    let max_task = length tasks
    let not_ready_task = maxBound

    response_task <- stateInit (named "response_task") $ ival not_ready_task

    -- Queue up to 1 request per task, which can arrive in any order.
    states <- forM (zip (map fromIntegral [min_task..max_task]) tasks) $ \ (taskId, taskBase@Task { .. }) -> do
      taskPending <- state $ (named $ taskName ++ "_pending")
      taskLastReq <- state $ (named $ taskName ++ "_last_req")

      handler taskReq (named taskName) $ do
        sendReq <- emitter reqChan 1
        callback $ \ req -> do
          was_pending <- deref taskPending
          assert $ iNot was_pending
          refCopy taskLastReq req
          store taskPending true

          current_task <- deref response_task
          when (current_task ==? no_task) $ do
            store response_task taskId
            emit sendReq $ constRef taskLastReq

      return TaskState { .. }

    let do_schedule sendReq = do
          conds <- forM states $ \ TaskState { .. } -> do
            pend <- deref taskPending
            return $ (pend ==>) $ do
              emit sendReq $ constRef taskLastReq
              store response_task taskId
          cond_ (conds ++ [true ==> store response_task no_task])

    handler ready (named "ready") $ do
      sendReq <- emitter reqChan 1
      callback $ const $ do_schedule sendReq

    handler resChan (named "response") $ do
      sendReq <- emitter reqChan 1
      emitters <- forM states $ \ st -> do
        e <- emitter (taskRes $ taskBase st) 1
        return (st, e)
      callback $ \ res -> do
        current_task <- deref response_task
        assert $ current_task >=? fromIntegral min_task
        assert $ current_task <=? fromIntegral max_task
        cond_ $ do
          (TaskState { .. }, e) <- emitters
          return $ (current_task ==? taskId ==>) $ do
            was_pending <- deref taskPending
            assert was_pending
            store taskPending false
            emit e res
        do_schedule sendReq
