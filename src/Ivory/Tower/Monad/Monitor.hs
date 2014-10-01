{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Ivory.Tower.Monad.Monitor
  ( Monitor
  , runMonitor
  , monitorPutASTHandler
  , monitorPutModules
  ) where

import MonadLib
import Control.Monad.Fix
import Control.Applicative

import Ivory.Tower.Types.Unique
import Ivory.Tower.Types.MonitorCode
import Ivory.Tower.Monad.Base
import Ivory.Tower.Monad.Tower
import qualified Ivory.Tower.AST as AST

import Ivory.Tower.ToyObjLang

newtype Monitor a = Monitor
  { unMonitor :: StateT AST.Monitor (StateT MonitorCode Tower) a
  } deriving (Functor, Monad, Applicative, MonadFix)

runMonitor :: String -> Monitor () -> Tower (AST.Monitor, MonitorCode)
runMonitor n b = do
  u <- freshname n
  runStateT emptyMonitorCode
              (fmap snd (runStateT (AST.emptyMonitor u) (unMonitor b)))

withAST :: (AST.Monitor -> AST.Monitor) -> Monitor ()
withAST f = Monitor $ do
  a <- get
  set (f a)

monitorPutASTHandler :: AST.Handler -> Monitor ()
monitorPutASTHandler a = withAST $
  \s -> s { AST.monitor_handlers = a : AST.monitor_handlers s }

monitorPutModules :: (AST.Monitor -> AST.Tower -> [Module]) -> Monitor ()
monitorPutModules ms = Monitor $ do
  a <- get
  lift $ lift $ towerPutModules $
    \t -> ms (findMonitorAST (AST.monitor_name a) t) t
  where
  findMonitorAST :: Unique -> AST.Tower -> AST.Monitor
  findMonitorAST n twr = maybe err id (AST.towerFindMonitorByName n twr)
  err = error "findMonitorAST failed - broken invariant"

instance BaseUtils Monitor where
  fresh = Monitor $ lift $ lift fresh
