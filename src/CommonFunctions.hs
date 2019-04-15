module CommonFunctions where

import Data.Char
import Data.List
import Data.List.Split
import Data.Either
import Types
import ErrM
import qualified Data.Map as Map
import Data.Maybe (fromJust)
import System.FilePath
import System.Directory
import Data.Functor
import Control.Lens hiding(Context,pre)
import Java.JavaLanguage


cmpScope :: Scope -> Scope -> Bool
cmpScope (InFor (ForId id')) (InTemp id) = isInfixOf id id' 
cmpScope (InTemp id') (InFor (ForId id)) = cmpScope (InFor (ForId id)) (InTemp id')
cmpScope scope scope' = scope == scope'

openingBracket :: String -> Bool
openingBracket "" = False
openingBracket s  = null (clean s) && elem '{' s

args2Str :: [Bind] -> String
args2Str []       = ""
args2Str (bn:bns) = case bn of
                         BindType t id -> t ++ " " ++ id ++ "," ++ args2Str bns
                         _ -> error "argst2Str: A trigger has a wrongly defined argument.\n"

getDuplicates :: Eq a => [a] -> [a]
getDuplicates []     = []
getDuplicates (x:xs) = if elem x xs 
                       then x:getDuplicates xs
                       else getDuplicates xs   

removeDuplicates :: Eq a => [a] -> [a]
removeDuplicates []     = []
removeDuplicates (x:xs) = if (elem x xs)
                          then removeDuplicates xs
                          else x:removeDuplicates xs

removeDuplicates' :: Eq a => [(a,a)] -> [(a,a)]
removeDuplicates' []            = []
removeDuplicates' (p@(xs,ys):xss) = 
 let zs = map fst xss
 in if (elem xs zs)
    then removeDuplicates' xss 
    else p:removeDuplicates' xss

getListOfTypesAndVars :: ClassInfo -> [(String, ClassInfo, JavaFilesInfo)] -> [(Modifier,Type, Id)]
getListOfTypesAndVars cl []                  = []
getListOfTypesAndVars cl ((main, cl',ts):xs) = if (cl == cl') 
                                               then varsInFiles ts
                                               else getListOfTypesAndVars cl xs

getListOfTypesAndMethods :: ClassInfo -> [(String, ClassInfo, JavaFilesInfo)] -> [(Type, Id,Modifier)]
getListOfTypesAndMethods cl []                  = []
getListOfTypesAndMethods cl ((main, cl',ts):xs) = 
 if (cl == cl') 
 then [(xy ^. _1, xy ^. _2, xy ^. _5) | xy <- methodsInFiles ts]
 else getListOfTypesAndMethods cl xs

getListOfArgs :: MethodName -> [(Type, Id,[String],MethodInvocations,Modifier)] -> [String]
getListOfArgs mn []                  = []
getListOfArgs mn ((t,mn',ts,_,_):xs) = if (mn == mn') 
                                       then ts
                                       else getListOfArgs mn xs

getBindArgs' :: [Bind] -> String
getBindArgs' []                     = ""
getBindArgs' [BindType t id]        = t ++ " " ++ id
getBindArgs' ((BindType t id):y:ys) = t ++ " " ++ id ++ "," ++ getBindArgs' (y:ys)
getBindArgs' _                      = ""

lookfor :: [(Trigger, [String])] -> Trigger -> [String]
lookfor [] _     = []
lookfor (x:xs) e = if (fst x==e)
                   then snd x
                   else lookfor xs e

lookforClVar :: PropertyName -> [(PropertyName, ClassInfo, String)] -> String
lookforClVar pn []              = ""
lookforClVar pn ((pn',_,cl):xs) = if pn == pn'
                                  then cl
                                  else lookforClVar pn xs

flattenArgs :: [Args] -> String
flattenArgs []               = ""
flattenArgs [(Args t id)]    = t ++ " " ++ id
flattenArgs ((Args t id):xs) = t ++ " " ++ id ++ "," ++ flattenArgs xs

getImports :: Imports -> String
getImports []            = ""
getImports (Import s:xs) = "import " ++ s ++ ";\n" ++ getImports xs

filterRefTypes :: [Args] -> [Args]
filterRefTypes []         = []
filterRefTypes (arg:args) = 
 case getArgsType arg of
      "Action"     -> filterRefTypes args
      "Condition"  -> filterRefTypes args
      "Trigger"    -> filterRefTypes args
      "MethodName" -> filterRefTypes args
      "HTriple"    -> filterRefTypes args
      xs           -> if elem xs primitiveJavaTypes
                      then filterRefTypes args
                      else arg:filterRefTypes args

--Maps translated template scope in Date to the scope of the template in the ppDATE
normaliseScope :: Scope -> Scope
normaliseScope (InFor xs) = 
 if (isInfixOf "_cact" (show xs))
 then case splitOn "_cact" (show xs) of
           [] -> error $ "Error when normalising a scope " ++ show (InFor xs)
           ys -> InTemp (head ys)           
 else InFor xs
normaliseScope scope      = scope

-------------------------
-- Methods for parsing --
-------------------------

readIdentifier :: String -> Err (String, String)
readIdentifier text 
  | identifier == "" = fail "Error Parsing: Expecting identifier, but none was found.\n"
  | otherwise        = return (identifier, text')
  where
    (identifier, text') = break (\c -> c == '}' || c == '{') text

isIdentifierSymbol :: Char -> Bool
isIdentifierSymbol c = isAlphaNum c || c == '_'

clean :: String -> String
clean = dropWhile (\ c -> isSpace c || c == '{' || c == '}')

trim :: String -> String
trim = reverse . clean . reverse . clean

cleanBack :: String -> String
cleanBack = reverse . clean . reverse

splitAtIdentifier :: Char -> String -> (String, String)
splitAtIdentifier iden s = (takeWhile (\c -> not (c == iden)) s, dropWhile (\c -> not (c == iden)) s)

splitAtClosingParen :: Int -> String -> (String, String)
splitAtClosingParen _ ""       = ("","")
splitAtClosingParen n ('(':xs) = 
 let (a,b) = splitAtClosingParen (n+1) xs
 in ('(':a,b)
splitAtClosingParen n (')':xs) = 
 if n > 0
 then let (a,b) = splitAtClosingParen (n-1) xs
      in (')':a,b)
 else ("",xs)
splitAtClosingParen n (x:xs) = 
 let (a,b) = splitAtClosingParen n xs
 in (x:a,b)

splitOnIdentifier :: String -> String -> [String]
splitOnIdentifier = splitOn

checkIfParseErrors :: [Either a b] -> Either [a] [b]
checkIfParseErrors es = let (ls, rs) = partitionEithers es
                        in if ((not.null) ls)
                           then Left ls
                           else Right rs

addComma :: [String] -> String
addComma = intercalate ","

---------------------------------------
-- Manipulating the parsed .xml file --
---------------------------------------

removeNoneHTs :: [Proof] -> [HTName] -> [Proof]
removeNoneHTs [] _       = []
removeNoneHTs (p:ps) cns = let cn = getHTNameErrConst (contractText p) (typee p) in
                                 if ((cn /= "") && elem cn cns)
                                 then p:removeNoneHTs ps cns
                                 else removeNoneHTs ps cns


getInfoFromProof :: Proof -> (MethodName, HTName, [String],String)
getInfoFromProof proof = let mn    = getMethodName' (target proof)
                             path  = typee proof
                             cn    = getHTNameErrConst (contractText proof) (typee proof)
                             npres = getNewPreConds (executionPath proof)
                             aoft  = length $ filter (=="true") npres
                         in if (aoft >= 1)
                            then if (aoft == 1) 
                                 then if (length npres == 1)
                                      then (mn, cn, npres,path) -- KeY has nothing to say about the proof
                                      else (mn, cn, filter (not.(=="true")) npres,path)
                                 else if (aoft == length npres)
                                      then (mn, cn, ["true"],path) -- KeY has nothing to say about the proof
                                      else (mn, cn, filter (not.(=="true")) npres,path)
                            else (mn, cn, npres,path)

getMethodName' :: Target -> MethodName
getMethodName' t = fst $ splitAtIdentifier '(' t                   

getHTNameErrConst :: ContractText -> Type -> HTName
getHTNameErrConst ctext t = let (_, xs) = splitAtIdentifier ':' ctext
                                ys      = splitOnIdentifier t (tail xs)
                            in if (length ys == 1)
                               then ""
                               else trim $ fst $ splitAtIdentifier '=' $ (tail.head.tail) ys

getHTNameErrVar :: ContractText -> HTName
getHTNameErrVar ctext = 
 let (_, xs) = splitAtIdentifier ':' ctext
     (_, ys) = splitAtIdentifier '.' $ tail xs
 in if (null ys)
    then ""
    else let (cn, _) = splitAtIdentifier '=' $ tail ys 
         in trim cn

getNewPreConds :: [EPath] -> [String]
getNewPreConds []       = []
getNewPreConds (ep:eps) = if (verified ep == "false") 
                          then pathCondition ep:getNewPreConds eps
                          else getNewPreConds eps

introduceOr :: [String] -> String
introduceOr [x]    = x
introduceOr (x:xs) = x ++ " || " ++ introduceOr xs

getTriggersFors :: Foreaches -> Triggers
getTriggersFors []     = []
getTriggersFors (f:fs) = getTriggersCtxt (f ^. getCtxtForeach) ++ getTriggersFors fs

getTriggersCtxt :: Context -> Triggers
getTriggersCtxt ctxt = ctxt ^. triggers ++ getTriggersFors (ctxt ^. foreaches)


makeAddFile :: Import -> IO (String, ClassInfo)
makeAddFile (Import s) = let xs = splitOnIdentifier "." s
                         in if (length xs == 1)
                            then return ("", head xs)
                            else let val = last xs
                                     ys = (init $ foldr (\ xs xss -> xs ++ "/" ++ xss) "" (init xs))
                                 in return (ys, val)

--------------------------------------------------------------
-- Copy all the files within a Directory to a new directory --
--------------------------------------------------------------

copyFiles source dest =
 do
    createDirectoryIfMissing True dest
    subItems <- getSubitems' source
    mapM_ (copyItem' source dest) subItems


getSubitems' :: FilePath -> IO [(Bool, FilePath)]
getSubitems' path = getSubitemsRec ""
  where
    getChildren path =  (\\ [".", ".."]) <$> getDirectoryContents path

    getSubitemsRec relPath = do
        let absPath = path </> relPath
        isDir <- doesDirectoryExist absPath
        children <- if isDir then getChildren absPath else return []
        let relChildren = [relPath </> p | p <- children]
        ((isDir, relPath) :) . concat <$> mapM getSubitemsRec relChildren

copyItem' baseSourcePath baseTargetPath (isDir, relativePath) =
 do
    let sourcePath = baseSourcePath </> relativePath
    let targetPath = baseTargetPath </> relativePath
    if isDir
    then createDirectoryIfMissing False targetPath
    else copyFile sourcePath targetPath

