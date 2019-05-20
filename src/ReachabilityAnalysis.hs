module ReachabilityAnalysis where

import qualified Data.Map.Strict as Map
import Control.Lens hiding(Context,pre)
import Types
import UpgradeAesir

reachabilityAnalysis :: UpgradeModel CModel -> IO (Map.Map NameState Transitions)
reachabilityAnalysis umodel = 
 let cmodel = getValue umodel
     model  = cmodel ^. modelGet ^. ctxtGet
 in do putStrLn (show $ initprop $ getEnvVal umodel)
       return Map.empty


createMapping :: Property -> Map.Map (NameState,PropertyName) Transitions
createMapping PNIL                      = Map.empty
createMapping (Property pn _ trs props) = 
 undefined
