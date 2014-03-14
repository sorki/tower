{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}

module Ivory.Tower.Compile.FreeRTOS
  ( os
  , searchDir
  ) where

import           GHC.TypeLits
import           Ivory.Language
import           Ivory.Stdlib
import           Ivory.Tower
import qualified Ivory.Tower.AST as AST
import qualified Ivory.Tower.Types.OS as OS
import           Ivory.Tower.Types.TaskCode
import           Ivory.Tower.Types.SystemCode
import           Ivory.Tower.Types.Unique
import           Ivory.Tower.Types.Time

import Ivory.Tower.Compile.FreeRTOS.SearchDir (searchDir)
import Ivory.Tower.Compile.FreeRTOS.MsgQueue
import Ivory.Tower.Compile.FreeRTOS.EventNotify

import qualified Ivory.OS.FreeRTOS.Task as Task
import qualified Ivory.OS.FreeRTOS.Time as Time

os :: OS.OS
os = OS.OS
  { OS.gen_channel     = gen_channel
  , OS.get_emitter     = get_emitter
  , OS.get_receiver    = get_receiver
  , OS.codegen_task    = codegen_task
  , OS.codegen_sysinit = codegen_sysinit
  }

gen_channel :: forall (n :: Nat) area
             . (SingI n, IvoryArea area, IvoryZero area)
            => AST.System
            -> AST.Chan
            -> Proxy n
            -> Proxy area
            -> (Def('[]:->()), ModuleDef)
gen_channel sys chan _ _ = (mq_init q, mq_code q)
  where
  q :: MsgQueue area
  q = msgQueue sys chan (Proxy :: Proxy n)

get_emitter :: forall area eff s
             . (IvoryArea area, IvoryZero area)
            => AST.System
            -> AST.Chan
            -> ConstRef s area
            -> Ivory eff ()
get_emitter sys chan = mq_push q
  where
  q :: MsgQueue area
  -- Expect that size doesn't matter here.
  q = msgQueue sys chan (Proxy :: Proxy 1)

get_receiver :: forall area eff s
              . (IvoryArea area, IvoryZero area)
             => AST.System
             -> AST.Task
             -> AST.Chan
             -> Ref s area
             -> Ivory eff IBool
get_receiver sys tsk chan = mq_pop q tsk
  where
  q :: MsgQueue area
  -- Expect that size doesn't matter here.
  q = msgQueue sys chan (Proxy :: Proxy 1)

time_mod :: Module
time_mod = package "tower_freertos_time" $ do
  incl time_proc
  Time.moddef

time_proc :: Def('[]:->ITime)
time_proc = proc "getTimeMicros" $ body $ do
  ticks <- call Time.getTickCount
  tickrate <- call Time.getTickRateMilliseconds
  ret (fromIMilliseconds (ticks * tickrate))

codegen_task :: AST.System
             -> AST.Task
             -> TaskCode
             -> ([Module],ModuleDef)
codegen_task _sys tsk taskcode = ([loop_mod, user_mod], deps)
  where
  deps = do
    depend user_mod
    depend loop_mod

  next_due_area = area (named "time_next_due") Nothing
  next_due_ref = addrOf next_due_area

  exit_guard_area = area (named "time_exit_guard") Nothing
  exit_guard_ref = addrOf exit_guard_area
  overrun_area = area (named "time_overrun") (Just (ival minBound))
  overrun_ref = addrOf overrun_area

  timeRemaining :: ITime -> ITime -> Ivory eff ITime
  timeRemaining nextdue now= do
    remaining <- assign (nextdue - now)
    when (remaining <? 0) $ store overrun_ref now
    return ((remaining >? 0) ? (remaining, 0))

  loop_proc :: Def('[]:->())
  loop_proc = proc (named "tower_task_loop") $ body $ noReturn $ do
    store next_due_ref 0
    call time_proc >>= store exit_guard_ref
    forever $ noBreak $ do
      time_enter_guard <- call time_proc
      time_exit_guard  <- deref exit_guard_ref
      dt <- assign (time_enter_guard - time_exit_guard)
      assert (dt >=? 0)

      time_next_due <- deref next_due_ref
      trem <- timeRemaining time_next_due time_enter_guard
      evtn_guard evt_notifier trem

      store next_due_ref maxBound
      taskcode_timer taskcode next_due_ref
      taskcode_eventrxer taskcode
      taskcode_eventloop taskcode

  evt_notifier = taskEventNotify tsk

  loop_mod = package (named "tower_task_loop") $ do
    depend user_mod
    depend time_mod
    depend (package "tower" (return ()))
    defMemArea next_due_area
    defMemArea exit_guard_area
    defMemArea overrun_area
    taskcode_commprim taskcode
    incl loop_proc
    evtn_code evt_notifier

  user_mod = package (named "tower_task_usercode") $ do
    depend loop_mod
    depend time_mod
    depend (package "tower" (return ()))
    taskcode_usercode taskcode

  named n = n ++ "_" ++ (showUnique (AST.task_name tsk))

codegen_sysinit :: AST.System
                -> SystemCode
                -> ModuleDef
                -> [Module]
codegen_sysinit _sysast syscode taskmoddefs = [time_mod, sys_mod]
  where
  taskasts = map fst (systemcode_tasks syscode)
  taskcodes = map snd (systemcode_tasks syscode)
  sys_mod = package "tower" $ do
    taskmoddefs
    systemcode_moddef syscode
    incl init_proc
    mapM_ (incl . taskarg_proc) taskasts
    Task.moddef

  init_proc :: Def('[]:->())
  init_proc = proc "tower_entry" $ body $ noReturn $ do
    systemcode_comm_initializers syscode
    mapM_ (evtn_init . taskEventNotify) taskasts
    mapM_ taskcode_init taskcodes
    mapM_ launch taskasts

  launch :: AST.Task -> Ivory eff ()
  launch taskast = call_ Task.begin tproc stacksize priority
    where
    tproc = Task.taskProc (taskarg_proc taskast)
    stacksize = 1024 -- XXX
    priority = 1 -- XXX

  taskarg_proc :: AST.Task -> Def('[Ref Global (Struct "taskarg")]:->())
  taskarg_proc taskast = proc (named "tower_task_entry") $ \_ -> body $ do
    call_ loop_proc
    -- loop_proc should never exit.
    where
    loop_proc :: Def('[]:->())
    loop_proc = proc (named "tower_task_loop") $ body $ undefined
    named n = n ++ "_" ++ (showUnique (AST.task_name taskast))

