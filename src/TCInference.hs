{-# LANGUAGE TemplateHaskell #-}

module TCInference where

import BRT
import Control.Lens hiding(Context,pre,children)
import Types
import CommonFunctions

tcInference :: BRT -> NameState -> FilePath -> IO ()
tcInference BNil _ _            =
  do putStrLn "An empty Backwards Reachability Tree was computed"
     putStrLn "Trace condition inference... [Aborted]\n"
tcInference t stToReach out_add =
  if null (t ^. children)
  then do putStrLn "Backwards reachability tree computation... [DONE]"
          putStrLn "Trace condition inference... \n"
          putStrLn "Amount of trace conditions generated: 1"
          putStrLn (show (TC "true" []))
          xmlOutTC [TC "true" []] out_add
          putStrLn "Trace condition inference... [DONE]\n"
  else do putStrLn "Backwards reachability tree computation... [DONE]"
          putStrLn "Trace condition inference... \n"
          let ret = seq2TraceConds $ prune (flattenBRT t) (t ^. initial)
          putStrLn $ "Amount of trace conditions generated: " ++ show (length ret)
          showAllTraces ret
          xmlOutTC ret out_add
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
         -> NameState -> [[(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))]]
prune [] _           = []
prune (xs:xss) start = prune_ xs start : prune xss start

prune_ :: [(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))]
         -> NameState -> [(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))]
prune_ [] _      = []
prune_ (x:xs) nm = if (\(y,_,_) -> y) x == nm
                   then x:xs
                   else prune_ xs nm

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

------------------------------------------------
-- Output file for generated trace conditions --
------------------------------------------------

xmlOutTC :: TraceConditions -> FilePath -> IO ()
xmlOutTC xs out_add =
  do let xs'     = map tc2xml xs
     let file    = out_add ++ "traces.xml"
     let content = mkHeader $ concatMap mkXMLout xs'
     writeFile file content

tc2xml :: TraceCondition -> TCXml
tc2xml (TC tr patt) = TCXml tr (showPatternElem patt)

mkXMLout :: TCXml -> String
mkXMLout (TCXml phi trace) =
  "  <TraceCondition formula=\"" ++ replaceSymbols phi symbolsXML ++ "\" "
  ++ "trace=\"&lt;&lt;" ++ trace ++ "&gt;&gt;\">\n"
  ++ "  </TraceCondition>\n"

mkHeader :: String -> String
mkHeader s =
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
  ++ "<result>\n"   ++ s ++ "</result>"

symbolsXML :: [(String,String)]
symbolsXML = [("&amp;","&&"), ("&gt;=",">="), ("&gt;", ">"), (" =","=="),
              ("&quot;","\""),("&apos;","\\"),("&lt;","<"),("&lt;=","<="),
              ("TRUE","true"),("FALSE","false")
             ]

replaceSymbols :: String -> [(String, String)] -> String
replaceSymbols [] _            = ""
replaceSymbols s []            = s
replaceSymbols s ((def,id):xs) =
  let ys = splitOnIdentifier id s
  in if (length ys == 1)
     then replaceSymbols s xs
     else replaceSymbols (head ys ++ (concat (map (def++) $ tail ys))) xs

data TCXml =
  TCXml { _formula :: String
        , _trace   :: String
        }

makeLenses ''TCXml
