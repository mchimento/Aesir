module ReachabilityAnalysis where

import qualified Data.Map.Strict as Map
import Control.Lens hiding(Context,pre)
import Types
import UpgradeAesir

reachabilityAnalysis :: UpgradeModel CModel -> IO (Map.Map NameState Transitions)
reachabilityAnalysis umodel = 
 let cmodel = getValue umodel
     model  = cmodel ^. modelGet
     ip     = initprop $ getEnvVal umodel
 in case lookforProp model ip of
         PNIL -> return Map.empty
         prop -> return $ createMapping prop ip


lookforProp :: Model -> IPropInfo -> Property
lookforProp model ip = 
 case ip ^. ipScope of
      TopLevel -> getProp (model ^. ctxtGet ^. property) ip
      InFor id -> undefined
      InTemp _ -> undefined

getProp :: Property -> IPropInfo -> Property
getProp PNIL _ = PNIL
getProp (Property pname states trans props) ip = 
 undefined
 
createMapping :: Property -> IPropInfo -> Map.Map NameState Transitions
createMapping PNIL _                       = Map.empty
createMapping (Property pn _ trs props) ip = 
 undefined
