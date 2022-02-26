module TCInference where

import BRT
import Control.Lens hiding(Context,pre,children)
import Types

tcInference :: BRT -> NameState -> IO ()
tcInference t stToReach =
  if null (t ^. children)
  then do putStrLn "Trace condition inference... \n"
          putStrLn "Amount of trace conditions generated: 1"
          putStrLn (show (TC "true" []))
          putStrLn "Trace condition inference... [DONE]\n"
  else do putStrLn "Trace condition inference... \n"
          let ret = seq2TraceConds $ prune (flattenBRT t) (t ^. initial) stToReach
          putStrLn $ "Amount of trace conditions generated: " ++ show (length ret)
          showAllTraces ret
          putStrLn "Trace condition inference... [DONE]\n"

flattenBRT :: BRT -> [[(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))]]
flattenBRT brt =
  let node = brt2elem brt
  in addNode_lift node False (map flattenBRT (brt ^. children))

addNode_lift node False []   = [[node]]
addNode_lift node True []    = []
addNode_lift node _ (xs:xss) = addNode node xs ++ addNode_lift node True xss

addNode :: a -> [[a]] -> [[a]]
addNode node []       = []
addNode node (xs:xss) = (xs++[node]) : addNode node xss

brt2elem :: BRT -> (NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))
brt2elem brt = (brt ^. current, brt ^. prop, brt ^. method)

prune :: [[(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))]]
         -> NameState -> NameState -> [[(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))]]
prune [] _ _           = []
prune (x:xs) start end =
  if checkForPrune x start end
  then prune xs start end
  else x : prune xs start end

checkForPrune :: [(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))]
                 -> NameState -> NameState -> Bool
checkForPrune [] _ _              = True
checkForPrune [(x,_,_)] start end = not (x == start && x == end)
checkForPrune xs start end =
  let hd = (\(x,_,_) -> x) (head xs) in
  let tl = (\(x,_,_) -> x) (last xs)
  in not (start == hd && end == tl)

seq2TraceConds :: [[(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))]] -> TraceConditions
seq2TraceConds []       = []
seq2TraceConds (xs:xss) =
  if null xs
  then seq2TraceConds xss
  else seq2TraceCond xs : seq2TraceConds xss

seq2TraceCond :: [(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))] -> TraceCondition
seq2TraceCond [] = TC "true" []
seq2TraceCond xs =
  let si    = head xs in
  let trace = map (\(_,_,z) -> z) $ init xs in
  let phi   = (\(_,x,_) -> x) si
  in TC phi trace

showAllTraces :: TraceConditions -> IO ()
showAllTraces []     = putStrLn ""
showAllTraces (x:xs) =
 do putStrLn (show x)
    showAllTraces xs
