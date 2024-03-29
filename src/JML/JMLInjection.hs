module JML.JMLInjection(injectJMLinitial,injectJMLannotations,setDummyVarsFalse) where

import Types
import JML.JMLGenerator
import CommonFunctions
import System.Directory
import Data.Char
import UpgradeAesir
import ErrM
import Java.JavaLanguage
import System.IO
import Control.DeepSeq
import Control.Lens hiding(Context,pre)
import Data.List

---------------------------------------
-- Injecting Initial JML annotations --
---------------------------------------

injectJMLinitial :: UpgradeModel CModel -> FilePath -> IO ()
injectJMLinitial m toAnalyse_add =
 do let (model, env)  = fromOK $ runStateT m emptyEnv
    let imports       = model ^. importsGet
    let cinvs         = model ^. cinvariantsGet
    let ys            = splitCInvariants cinvs []
    let jinfo         = javaFilesInfo env
    let imports'      = [i | i <- imports,not (elem ((\ (Import s) -> s) i) importsInKeY)]
    sequence_ $ map (\ i -> annotateInitTmpFiles i toAnalyse_add jinfo ys) imports'


annotateInitTmpFiles :: Import -> FilePath -> [(String, ClassInfo, JavaFilesInfo)]
                    -> [(Class, CInvariants)]
                    -> IO ()
annotateInitTmpFiles i output_add jinfo ys =
  do (main, cl) <- makeAddFile i
     let output_add' = output_add ++ "/" ++ main
     createDirectoryIfMissing True output_add'
     let file         = output_add' ++ "/" ++ (cl ++ ".java")
     r <- readFile file
     let cinvs      = generateTmpFileCInv cl ys r
     let specPublic = updateSpecPublic cl jinfo cinvs
     rnf specPublic `seq` (writeFile file specPublic)
     --use of rnf [s] `seq` [...] to force reading the content of the
     --file and close it

-------------------------------------------------
-- Injecting JML annotations for Hoare triples --
-------------------------------------------------

injectJMLannotations :: UpgradeModel CModel -> FilePath -> HTriples -> IO ()
injectJMLannotations ppd toAnalyse_add hts =
 do createDirectoryIfMissing False toAnalyse_add
    prepareTmpFiles ppd toAnalyse_add hts
    return ()


prepareTmpFiles :: UpgradeModel CModel -> FilePath -> HTriples -> IO [()]
prepareTmpFiles m output_add hts =
 do let (model, env)  = fromOK $ runStateT m emptyEnv
    let imports       = model ^. importsGet
    let xs            = splitClassHT hts
    let join_xs       = joinClassHT xs []
    let consts_jml    = getHTs hts
    let imports'      = [i | i <- imports,not (elem ((\ (Import s) -> s) i) importsInKeY)]
    sequence $ map (\ i -> annotateTmpFiles i output_add join_xs consts_jml) imports'


annotateTmpFiles :: Import -> FilePath ->
                    [(ClassInfo, [HTName])] -> HTjml -> IO ()
annotateTmpFiles i output_add jxs consts_jml =
  do (main, cl) <- makeAddFile i
     let output_add' = output_add ++ "/" ++ main
     createDirectoryIfMissing True output_add'
     let file         = output_add' ++ "/" ++ (cl ++ ".java")
     r <- readFile file
     let dummyVars  = generateDBMFile cl jxs r
     let contracts  = genTmpFilesConst (main,cl) consts_jml dummyVars
     rnf contracts `seq` (writeFile file contracts)


---------------------------------------------
-- Injecting JML annotations for contracts --
---------------------------------------------

genTmpFilesConst :: (String, ClassInfo) -> HTjml -> String -> String
genTmpFilesConst (main, cl) [] r     = r
genTmpFilesConst (main, cl) (x:xs) r =
 let mn  = x ^. _1
     cl' = x ^. _2
     ov  = x ^. _3
     jml = x ^. _4
 in do if (cl == cl')
       then do let (ys, zs) = if (mn == cl)
                              then lookForConstructorDef mn (lines r)
                              else lookForMethodDef mn ov (lines r)
               let r' = (unlines ys) ++ jml ++ (unlines zs)
               genTmpFilesConst (main, cl) xs r'
       else genTmpFilesConst (main, cl) xs r


lookForMethodDef :: MethodName -> Overriding -> [String] -> ([String], [String])
lookForMethodDef mn _ []        = error $ "Something went wrong when annotating the method " ++ mn ++ ".\n"
lookForMethodDef mn ov (xs:xss) =
 let ys = splitOnIdentifier mn xs
 in if (length ys == 1)
    then (xs:a, b) --method name does not appear in the line
    else let zs     = (clean.head.tail) ys
             beginl = (words.head) ys
         in if ((head zs) == '(')
            then if (length beginl == 1)
                 then (xs:a, b) --not a method definition (does not have modifier or type)
                 else let ws = (clean.head) beginl
                      in if (elem ws javaModifiers)
                         then let ts = splitOnIdentifier "," $ fst $ splitAtClosingParen 0 $ tail zs in
                              if checkArguments ov ts
                              then ([], xs:xss)
                              else (xs:a, b) --not the intended method (overloading)
                         else (xs:a, b) --not a method definition (does not start with modifier)
            else (xs:a, b) --not referring to a method
                where (a, b) = lookForMethodDef mn ov xss

checkArguments :: Overriding -> [String] -> Bool
checkArguments _ []           = False
checkArguments OverNil _      = True
checkArguments (Over []) [[]] = True
checkArguments (Over []) _    = False
checkArguments (Over ts) [[]] = False
checkArguments (Over ts) ts'  =
 let types = map (head.words) ts'
 in ts == types

lookForConstructorDef :: MethodName -> [String] -> ([String], [String])
lookForConstructorDef mn []       = error $ "Something went wrong when checking the constructor " ++ mn ++ ".\n"
lookForConstructorDef mn (xs:xss) =
 let ys = splitOnIdentifier mn xs
 in if (length ys <= 1 || length ys > 2)
    then (xs:a, b)
    else let zs     = (clean.head.tail) ys
             beginl = (clean.head) ys
         in if (null beginl || elem beginl javaModifiers)
            then if ((head zs) == '(')
                 then ([], xs:xss)
                 else (xs:a, b)
            else (xs:a, b)
                where (a, b) = lookForConstructorDef mn xss

-------------------------------------------
-- Adds spec_public to private variables --
-------------------------------------------

updateSpecPublic :: String -> [(String, ClassInfo, JavaFilesInfo)] -> String -> String
updateSpecPublic cl jinfo r =
 let varsc    = getListOfTypesAndVars cl jinfo
     methodsc = getListOfTypesAndMethods cl jinfo
     (ys, zs) = lookForClassBeginning cl (lines r)
 in (unlines ys) ++ (unlines (searchAndAnnotateMethods (searchAndAnnotateVarsSP zs varsc) methodsc))

searchAndAnnotateVarsSP :: [String] -> [(String, String, String)] -> [String]
searchAndAnnotateVarsSP xss []     = xss
searchAndAnnotateVarsSP xss (ys:yss) =
 if (ys ^._1 == "private" || ys ^._1 == "protected")
 then let xss' = annotateSpecPublic ys xss
      in searchAndAnnotateVarsSP xss' yss
 else searchAndAnnotateVarsSP xss yss

annotateSpecPublic :: (String,String, String) -> [String] -> [String]
annotateSpecPublic (mod,t,v) []       = []
annotateSpecPublic (mod,t,v) (xs:xss) =
 let ident = t ++ " " ++ v
     ys    = splitOnIdentifier ident xs
 in if (length ys == 1)
    then xs:annotateSpecPublic (mod,t, v) xss
    else let xs' = (head ys) ++ " /*@ spec_public @*/ " ++ ident ++ (head.tail) ys
         in xs':xss

searchAndAnnotateMethods :: [String] -> [(String, String, String)] -> [String]
searchAndAnnotateMethods xss []     = xss
searchAndAnnotateMethods xss (ys:yss) =
 if (ys ^._3 == "private" || ys ^._3 == "protected")
 then let xss' = annotateSpecPublicM ys xss
      in searchAndAnnotateMethods xss' yss
 else searchAndAnnotateMethods xss yss

annotateSpecPublicM :: (String,String, String) -> [String] -> [String]
annotateSpecPublicM (t,v,mod) []       = []
annotateSpecPublicM (t,v,mod) (xs:xss) =
 let ident = t ++ " " ++ v
     ys    = splitOnIdentifier ident xs
 in if (length ys == 1)
    then xs:annotateSpecPublicM (t, v, mod) xss
    else let xs' = (head ys) ++ " /*@ spec_public @*/ " ++ ident ++ (head.tail) ys
         in xs':xss

-------------------------------------
-- Adds nullable to class variables --
-------------------------------------

updateTmpFileCInv :: String -> [(String, ClassInfo, JavaFilesInfo)] -> String -> String
updateTmpFileCInv cl jinfo r =
 let varsc    = getListOfTypesAndVars cl jinfo
     (ys, zs) = lookForClassBeginning cl (lines r)
 in (unlines ys) ++ (unlines (searchAndAnnotateVars zs varsc))

searchAndAnnotateVars :: [String] -> [(String, String, String)] -> [String]
searchAndAnnotateVars xss []               = xss
searchAndAnnotateVars xss ((mods,t,v):yss) =
 if (elem t primitiveJavaTypes)
 then searchAndAnnotateVars xss yss
 else let xss' = annotateNullable (t,v) xss
      in searchAndAnnotateVars xss' yss

--TODO: This method may need to be upgraded
annotateNullable :: (String, String) -> [String] -> [String]
annotateNullable (t, v) []       = []
annotateNullable (t, v) (xs:xss) =
 let ident = t ++ " " ++ v
     ys    = splitOnIdentifier ident xs
 in if (length ys == 1)
    then xs:annotateNullable (t, v) xss
    else let xs' = (head ys) ++ " /*@ nullable @*/ " ++ ident ++ (head.tail) ys
         in xs':xss


----------------------------------------------------
-- Injecting JML annotations for Class Invariants --
----------------------------------------------------

splitCInvariants :: CInvariants -> [(Class, CInvariants)] -> [(Class, CInvariants)]
splitCInvariants [] acum           = acum
splitCInvariants (cinv:cinvs) acum = splitCInvariants cinvs (updateAcum cinv acum)

updateAcum :: CInvariant -> [(Class, CInvariants)] -> [(Class, CInvariants)]
updateAcum cinv@(CI class' body) []               = [(class', [cinv])]
updateAcum cinv@(CI class' body) ((cl, cinvs):as) =
 if (class' == cl)
 then (cl, cinv:cinvs):as
 else (cl,cinvs):updateAcum cinv as

generateTmpFileCInv :: String -> [(Class, CInvariants)] -> String -> String
generateTmpFileCInv cl xs r =
 let cinvs_jml = getCInvariants $ getCInvs' xs cl
     (ys, zs)  = lookForClassBeginning cl (lines r)
 in (unlines ys) ++ cinvs_jml ++ (unlines zs)

lookForClassBeginning :: ClassInfo -> [String] -> ([String], [String])
lookForClassBeginning c []       = error $  "Something went wrong when checking a class invariant for the class " ++ c  ++ ".\n"
lookForClassBeginning c (xs:xss) = let ys = splitOnIdentifier ("class " ++ c) xs
                                   in if (length ys == 1)
                                      then (xs:a, b)
                                      else let (ts,zs) = splitAtIdentifier '{' $ (head.tail) ys
                                           in if (null zs)
                                              then splitOpeningBracket (xs:xss)
                                              else ([xs], xss)
                                           where (a, b) = lookForClassBeginning c xss


splitOpeningBracket :: [String] -> ([String],[String])
splitOpeningBracket []       = ([],[])
splitOpeningBracket (xs:xss) =
 let ys = splitOnIdentifier "{" xs
 in if (length ys == 1)
    then (xs:a,b)
    else ([xs++"\n"],"\n":xss)
       where (a,b) = splitOpeningBracket xss

getCInvs' :: [(Class, CInvariants)] -> Class -> CInvariants
getCInvs' [] _           = []
getCInvs' ((cl', cinvs):xs) cl = if (cl' == cl)
                                then cinvs
                                else getCInvs' xs cl

---------------------------------------
-- Injecting dummy boolean variables --
---------------------------------------

generateDBMFile :: String -> [(ClassInfo, [HTName])] -> String -> String
generateDBMFile cl xs r =
 let dummy_vars = map (\xs -> genDummyVarJava "true" xs ++ "\n") $ lookForConstsNames cl xs
     (ys, zs)   = lookForClassBeginning cl (lines r)
 in (unlines ys) ++ concat dummy_vars ++ (unlines zs)


genDummyVarJava :: String -> HTName -> String
genDummyVarJava t cn = "  public static final boolean " ++ cn ++ " = " ++ t ++ ";"

lookForConstsNames :: ClassInfo -> [(ClassInfo, [HTName])] -> [HTName]
lookForConstsNames cn []             = []
lookForConstsNames cn ((cn', cs):xs) = if (cn == cn')
                                       then cs
                                       else lookForConstsNames cn xs

splitClassHT :: HTriples -> [(ClassInfo, HTName)]
splitClassHT []     = []
splitClassHT (c:cs) = (_methodCN c ^. clinf, c ^. htName) : splitClassHT cs

joinClassHT :: [(ClassInfo, HTName)] -> [(ClassInfo, [HTName])] -> [(ClassInfo, [HTName])]
joinClassHT [] jcc     = jcc
joinClassHT (x:xs) jcc = joinClassHT xs (updateJCC x jcc)

updateJCC :: (ClassInfo, HTName) -> [(ClassInfo, [HTName])] -> [(ClassInfo, [HTName])]
updateJCC (cn, c) []            = [(cn, [c])]
updateJCC (cn, c) ((cn',cs):xs) = if (cn == cn')
                                  then (cn', c:cs) : xs
                                  else (cn', cs):updateJCC (cn, c) xs

------------------------------------------------------------
-- Set dummy variables to false                           --
-- (to prevent multiple checks of the same Hoarte triple) --
------------------------------------------------------------

setDummyVarsFalse :: UpgradeModel CModel -> FilePath -> HTriples -> IO [()]
setDummyVarsFalse cm output_add hts =
 do let (model, env)  = fromOK $ runStateT cm emptyEnv
    let imports       = model ^. importsGet
    let imports'      = [i | i <- imports,not (elem ((\ (Import s) -> s) i) importsInKeY)]
    sequence $ map (\ i -> setDummyVarFalse i output_add hts) imports'

setDummyVarFalse :: Import -> FilePath -> HTriples -> IO ()
setDummyVarFalse i output_add hts  =
  do (main, cl) <- makeAddFile i
     let output_add' = output_add ++ "/" ++ main
     let file        = output_add' ++ "/" ++ (cl ++ ".java")
     r <- readFile file
     let vars = [ ht^.htName | ht <- hts, (_clinf (_methodCN ht)) == cl ]
     let (ys, zs) = lookForClassBeginning cl (lines r)
     let content  = (unlines ys) ++ (unlines (setFalseHT vars zs))
     rnf content `seq` (writeFile file content)

setFalseHT :: [HTName] -> [String] -> [String]
setFalseHT [] xss     = xss
setFalseHT (y:ys) xss = setFalseHT ys (setFalse y xss)

setFalse :: HTName -> [String] -> [String]
setFalse name []     = []
setFalse name (x:xs) =
 if isInfixOf (genDummyVarJava "true" name) x
 then genDummyVarJava "false" name:xs
 else x:setFalse name xs
