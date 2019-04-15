{-# LANGUAGE TemplateHaskell #-}

module UpgradeAesir where

import Types
import CommonFunctions
import Control.Monad
import Control.Monad.Writer
import qualified Control.Monad.State as CM
import qualified Data.Map.Strict as Map
import qualified ParserModel.Absaesir as Abs
import qualified ParserActions.AbsActions as Act
import ErrM
import ParserModel.Printaesir
import qualified ParserActions.PrintActions as PrintAct
import qualified JML.PrintJml as PrintJML
import ParserModel.Parser
import qualified ParserActions.ParserAct as ParAct
import qualified JML.ParserJML as ParJML
import Data.List
import Data.Either
import Data.Maybe
import Control.Lens hiding(Context,pre)
import Java.JavaLanguage


upgradeModel :: Abs.AbsModel -> UpgradeModel CModel
upgradeModel (Abs.AbsModel imports model temps cinvs consts methods) =
 chainExec (imports, model, temps, cinvs, consts, methods) (CModel [] nilModel TempNil [] (IProp "" "") []) emptyEnv [] 1
          where nilModel = undefined --Hack. This should not affect the execution of the tool.
                              
chainExec :: (Abs.Imports, Abs.Model, Abs.Templates, Abs.CInvariants, Abs.IProp, Abs.Methods) -> CModel -> Env -> [String] -> Int -> UpgradeModel CModel
chainExec modelp model env errs 6 = 
 if null errs
 then do put env
         return model
 else fail $ concat errs
chainExec modelp model env errs n = 
 case n of
      1 -> let model'  = importsGet .~ genImports (modelp ^. _1) $ model
               model'' = methodsGet .~ genMethods (modelp ^. _6) $ model' 
           in let imps  = model' ^. importsGet
                  imps' = getDuplicates imps
              in if (null imps') 
                 then chainExec modelp model'' env errs 2
                 else chainExec modelp model'' env (errs ++ (duplicateImps imps')) 2
      2 -> case runWriter (genIProp (modelp ^. _5)) of
                (iprop', [])  -> chainExec modelp (initpropGet .~ iprop' $ model) env errs 3
                (iprop', err) -> chainExec modelp (initpropGet .~ iprop' $ model) env (err:errs) 3
      3 -> case runStateT (genTemplates (modelp ^. _3)) env of
                Bad s            -> chainExec modelp model env (s:errs) 4
                Ok (temps',env') -> chainExec modelp (templatesGet .~ temps' $ model) env' errs 4
      4 -> case runStateT (genModel (modelp ^. _2)) env of
                Bad s             -> chainExec modelp model env (s:errs) 5
                Ok (model', env') -> chainExec modelp (modelGet .~ model' $ model) env' errs 5
      5 -> case runStateT (genClassInvariants (modelp ^. _4)) env of
                Bad s            -> chainExec modelp model env (s:errs) 6
                Ok (cinvs',env') -> chainExec modelp (cinvariantsGet .~ cinvs' $ model) env' errs 6

-------------
-- Imports --
-------------

genImports :: Abs.Imports -> Imports
genImports (Abs.ImportsNil)   = []
genImports (Abs.Imports imps) =
 let jfss = map getImportAbs imps
 in map (Import . joinImport . map (getIdAbs.getJFAbs)) jfss

duplicateImps :: Imports -> [String]
duplicateImps = map (\imp -> "Error: Multiple imports for " ++ (\(Import s) -> s) imp ++ ".\n")

----------------------
-- Initial Property --
----------------------

genIProp :: Abs.IProp -> Writer String IProp
genIProp (Abs.IProp id jml) = 
 case runWriter (getJML jml "initial property.") of
      (jml', []) -> return $ IProp (getIdAbs id) jml'
      (_,errs)   -> fail errs

-----------
-- Model --
-----------

genModel :: Abs.Model -> UpgradeModel Model
genModel = undefined

---------------
-- Templates --
---------------

genTemplates :: Abs.Templates -> UpgradeModel Templates
genTemplates = undefined

-----------------
-- CInvariants --
-----------------

genClassInvariants :: Abs.CInvariants -> UpgradeModel CInvariants
genClassInvariants = undefined

-------------
-- Methods --
-------------

genMethods :: Abs.Methods -> Methods
genMethods m = printTree m

------------------------
-- Selector functions --
------------------------

getArgs :: Abs.Args -> Args
getArgs (Abs.Args t id) = Args (getTypeAbs t) (getIdAbs id)

getArgsAbs :: Abs.Args -> (Type,Id)
getArgsAbs (Abs.Args t id) = (getTypeAbs t, getIdAbs id)

getSymbolsAbs :: Abs.Symbols -> String
getSymbolsAbs (Abs.Symbols s) = s

getIdAbs :: Abs.Id -> String
getIdAbs (Abs.Id s) = s

getTypeAbs :: Abs.Type -> String
getTypeAbs (Abs.Type (Abs.TypeDef (Abs.Id id))) = id
getTypeAbs (Abs.Type (Abs.TypeGen (Abs.Id id) (Abs.Symbols s1) xs (Abs.Symbols s2))) = id ++ s1 ++ addComma (map getIdAbs xs) ++ s2
getTypeAbs (Abs.Type (Abs.TypeArray (Abs.Id id))) = id

getJFAbs :: Abs.JavaFiles -> Abs.Id
getJFAbs (Abs.JavaFiles id) = id

getImportAbs :: Abs.Import -> [Abs.JavaFiles]
getImportAbs (Abs.Import jfs) = jfs

getVarInitAbs :: Abs.VariableInitializer -> VariableInitializer
getVarInitAbs Abs.VarInitNil     = VarInitNil
getVarInitAbs (Abs.VarInit vexp) = VarInit (printTree vexp)

getVarsAbs :: Abs.Vars -> Abs.Bind
getVarsAbs (Abs.Vars bind) = bind

getConstNameAbs :: Abs.HTName -> Abs.Id
getConstNameAbs (Abs.CN id) = id

getJML :: Abs.JML -> String -> Writer String JMLExp
getJML jml str = 
 let jml' = printTree jml in
 case ParJML.parse jml' of
      Bad s -> do tell $ "Error: Parse error on the " ++ str
                  return "Error: Parse error "
      Ok _  -> return jml' 

getJava :: Abs.Java -> Java
getJava java = printTree java

-------------------------
-- Auxiliary functions --
-------------------------

-- Imports are considered to be separated by '.'
joinImport :: [String] -> String
joinImport []     = ""
joinImport [ys]   = ys
joinImport (xs:ys:iss) = xs ++ "." ++ joinImport (ys:iss)

---------------------------------------------
-- Environment with Model spec information --
---------------------------------------------

data Env = Env
 { allTriggers     :: [TriggersInfo]
 , javaFilesInfo   :: [(JPath, ClassInfo, JavaFilesInfo)]
 , varsInModel       :: Variables                    
 , tempsInfo       :: [(Id,[Args])]--[(name_template, args_of_template)]
 , propInForeach   :: [(PropertyName, ClassInfo, String)]-- is used to avoid ambigous reference to variable id in foreaches
 , actes           :: [Id] --list of all defined action events
 , allCreateAct    :: [CreateActInfo]--list of all actions \create used in the transitions of the model
 }
  deriving (Show)

type UpgradeModel a = CM.StateT Env Err a

emptyEnv :: Env
emptyEnv = Env { allTriggers     = []
               , javaFilesInfo   = []
               , varsInModel     = []
               , tempsInfo       = []
               , propInForeach   = []
               , actes           = []
               , allCreateAct    = []
               }

getClassVarName :: Trigger -> MethodName -> [Bind] -> Bind -> String -> Scope -> [Args] -> UpgradeModel (ClassInfo,String)
getClassVarName _ _ args BindStar _ _ _                     = return ("*","")
getClassVarName _ _ args BindStarExec _ _ _                 = return ("*","")
getClassVarName _ _ args BindStarCall _ _ _                 = return ("*","")
getClassVarName _ _ args (BindType t id) _ _ _              = return (t,id)
getClassVarName _ _ args (BindTypeExec t id) _ _ _          = return (t,id)
getClassVarName _ _ args (BindTypeCall t id) _ _ _          = return (t,id)
getClassVarName tr mn args bindid s scope argsTemp = 
 let id  = getIdBind bindid 
     ts' = [getBindTypeType arg | arg <- args, getIdBind arg == id ]
     ts  = if (null ts') then prepareValUpd mn s id s else ts'
 in if (length ts /= 1)
    then if tempScope scope
         then let xs = [ getArgsType arg | arg <- argsTemp, getArgsId arg == id]
              in if null xs 
                 then return ("",id)
                 else return (head xs,id)
         else fail $ "The trigger " ++ tr ++ " does not include a class variable declaration.\n" 
    else return (head ts,id)
 
prepareValUpd :: MethodName -> String -> String -> String -> [String]
prepareValUpd mn s id chan = 
 if mn == "new"
 then [id]
 else if null s
      then []
      else [chan]

updateInfo :: Map.Map MethodName [(Id, String, [Args],Scope)] -> MethodName -> (Id, String, [Args],Scope) -> Map.Map MethodName [(Id, String, [Args],Scope)]
updateInfo m mn einfo = 
 case Map.lookup mn m of
      Nothing -> Map.insert mn [einfo] m
      Just xs -> Map.insert mn (einfo:xs) m


----------------------------
-- Monad State operations --
----------------------------

--get = CM.get
put = CM.put
runStateT = CM.runStateT

getValue :: UpgradeModel a -> a
getValue uppd = fst . fromOK $ runStateT uppd emptyEnv

getEnvVal :: UpgradeModel a -> Env
getEnvVal uppd = snd . fromOK $ runStateT uppd emptyEnv

