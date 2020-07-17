{-# LANGUAGE TemplateHaskell #-}

module BRTComputation where

import qualified Data.Map.Strict as Map
import Control.Lens
import Types
import UpgradeAesir
import BRT

defaultIter :: Integer
defaultIter = 2

brtAux :: BRT
brtAux = undefined

computeBRT :: UpgradeModel CModel -> Map.Map NameState Transitions -> IO BRT
computeBRT cm mp = 
 do putStrLn "Backwards reachability tree computation... [DONE]\n"
    return brtAux
