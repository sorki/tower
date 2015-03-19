{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Ivory.Tower.Backend.Compat where

import Control.Arrow (second)
import qualified Data.Map as Map
import Data.Monoid
import Ivory.Language
import qualified Ivory.Tower.AST as AST
import Ivory.Tower.Backend
import Ivory.Tower.Codegen.Emitter
import Ivory.Tower.Codegen.Handler
import Ivory.Tower.Types.EmitterCode
import Ivory.Tower.Types.GeneratedCode
import Ivory.Tower.Types.HandlerCode
import Ivory.Tower.Types.MonitorCode
import Ivory.Tower.Types.ThreadCode

data CompatBackend = CompatBackend

instance TowerBackend CompatBackend where
  newtype TowerBackendCallback CompatBackend a = CompatCallback (forall s. AST.Handler -> AST.Thread -> (Def ('[ConstRef s a] :-> ()), ModuleDef))
  newtype TowerBackendEmitter CompatBackend = CompatEmitter (AST.Tower -> AST.Thread -> SomeEmitterCode)
  data TowerBackendHandler CompatBackend a = CompatHandler AST.Handler (AST.Monitor -> AST.Tower -> AST.Thread -> ThreadCode)
  newtype TowerBackendMonitor CompatBackend = CompatMonitor (AST.Tower -> GeneratedCode)
  newtype TowerBackendOutput CompatBackend = CompatOutput GeneratedCode

  callbackImpl _ ast f = CompatCallback $ \ h -> callbackCode ast (AST.handler_name h) f

  emitterImpl _ ast =
    let (e, code) = emitterCode ast
    in (e, CompatEmitter $ \ twr thd -> SomeEmitterCode $ code twr thd)

  handlerImpl _ ast emitters callbacks = CompatHandler ast $ \ mon twr thd -> handlerCodeToThreadCode twr thd mon ast hc
    where
    hc = HandlerCode
      { handlercode_callbacks = \ t -> second mconcat $ unzip [ c ast t | CompatCallback c <- callbacks ]
      , handlercode_emitters = \ twr t -> [ e twr t | CompatEmitter e <- emitters ]
      }

  monitorImpl _ ast handlers moddef = CompatMonitor $ \ twr -> mempty
    { generatedcode_threads = Map.fromListWith mappend
        [ (thd, h ast twr thd)
        -- handlers are reversed to match old output for convenient diffs
        | SomeHandler (CompatHandler hast h) <- reverse handlers
        , thd <- AST.handlerThreads twr hast
        ]
    , generatedcode_monitors = Map.singleton ast $ MonitorCode moddef
    }

  towerImpl _ ast monitors = CompatOutput $ mconcat [ m ast | CompatMonitor m <- monitors ]