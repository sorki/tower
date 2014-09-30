{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Ivory.Tower.Monad.Handler
  ( Handler
  , runHandler
  , handlerPutASTEmitter
  , handlerPutASTCallback
  , handlerPutModule
  ) where

import MonadLib
import Control.Monad.Fix
import Control.Applicative

import Ivory.Tower.Types.Unique
import Ivory.Tower.Monad.Base
import Ivory.Tower.Monad.Monitor
import qualified Ivory.Tower.AST as AST

import Ivory.Tower.ToyObjLang

newtype Handler a = Handler
  { unHandler :: StateT AST.Handler Monitor a
  } deriving (Functor, Monad, Applicative, MonadFix)

runHandler :: String -> AST.Chan -> Handler () -> Monitor AST.Handler
runHandler n c b = do
  f <- fresh
  let h = AST.emptyHandler (Unique n f) c
  fmap snd (runStateT h (unHandler b))

withAST :: (AST.Handler -> AST.Handler) -> Handler ()
withAST f = Handler $ do
  a <- get
  set (f a)

handlerPutASTEmitter :: AST.Emitter -> Handler ()
handlerPutASTEmitter a = withAST (AST.handlerInsertEmitter a)

handlerPutASTCallback :: String -> Handler ()
handlerPutASTCallback a = withAST (AST.handlerInsertCallback a)

handlerPutModule :: (AST.Handler -> AST.Monitor -> AST.Tower -> Module)
                 -> Handler ()
handlerPutModule m = Handler $ do
  a <- get
  lift $ monitorPutModule $
    \mon t -> m (findHandlerAST (AST.handler_name a) mon) mon t
  where
  -- XXX FIXME
  findHandlerAST :: Unique -> AST.Monitor -> AST.Handler
  findHandlerAST = undefined

instance BaseUtils Handler where
  fresh = Handler $ lift fresh
