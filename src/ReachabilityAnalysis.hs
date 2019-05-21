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
      InFor id -> lookforPropInFor (model ^. ctxtGet ^. foreaches) ip
      InTemp _ -> undefined --TODO: Fix if templates are added to the model language

lookforPropInFor :: Foreaches -> IPropInfo -> Property
lookforPropInFor [] _      = PNIL
lookforPropInFor (x:xs) ip = 
 if (ip ^. ipScope == InFor (x ^. getIdForeach))
 then getProp (x ^. getCtxtForeach ^. property) ip
 else lookforPropInFor xs ip

getProp :: Property -> IPropInfo -> Property
getProp PNIL _                             = PNIL
getProp prop@(Property pname _ _ props) ip = 
 if (pname == ip ^. ipPropn)
 then prop
 else getProp props ip
 
createMapping :: Property -> IPropInfo -> Map.Map NameState Transitions
createMapping PNIL _                    = Map.empty
createMapping (Property _ sts trs _) ip = 
 let states = getStarting sts ++ getAccepting sts ++ getNormal sts ++ getBad sts 
 in undefined

getTransForSt :: State -> Transitions -> (State,Transitions)
getTransForSt s []     = (s,[])
getTransForSt s (t:ts) = 
 
