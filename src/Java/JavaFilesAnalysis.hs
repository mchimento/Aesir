module Java.JavaFilesAnalysis(javaStaticAnalysis) where 

import Language.Java.Parser
import Language.Java.Syntax
import Language.Java.Pretty
import Language.Java.Lexer
import Java.JavaParser
import Java.JavaLanguage
import qualified Types as T
import UpgradeAesir
import ErrM
import CommonFunctions
import Control.Lens hiding(Context,pre,Empty)
import System.Directory

-----------------------------------
-- Static analysis of java files --
-----------------------------------

javaStaticAnalysis :: UpgradeModel T.CModel -> FilePath -> [T.Flag] -> IO (UpgradeModel T.CModel)
javaStaticAnalysis model jpath flags = 
 do let imports = T._importsGet (fst . fromOK $ runStateT model emptyEnv)
    info <- sequence [ getJavaInfo i jpath
                     | i <- imports, not (elem ((\ (T.Import s) -> s) i) importsInKeY)
                     ] 
    return $ model >>= (\x -> do env <- get ; put (env { javaFilesInfo = info }) ; return x)

getJavaInfo :: T.Import -> FilePath -> IO (T.JPath, T.ClassInfo,T.JavaFilesInfo)
getJavaInfo i jpath = 
 do (main, cl) <- makeAddFile i
    let file_add = jpath ++ main ++ "/" ++ (cl ++ ".java")
    b <- doesFileExist file_add
    if b     
    then do r <- readFile file_add
            let java     = (\(Right x) -> x) $ parseJavaFile r
            let java_aux = lookForCTD cl $ map getClassDecls $ getClassTypeDecls java
            let vars     = getVariables java_aux
            let methods  = getMethods java_aux
            let jinfo    = T.JavaFilesInfo vars methods
            return (main, cl, jinfo)
    else error $ "Aesir: The file " ++ file_add ++ " does not exist.\n"

--
--Gets the variables of all the java files involved in the verification process
--
getVariables :: ClassDecl -> [(String,String, String)]
getVariables = splitVars . (map getVarsInfo) . (getVarDecl'.getMemberDecl.getDecls.getClassBody)

--
--Gets the method declarations of all the java files involved in the verification process
--      
getMethods :: ClassDecl -> [(String, String, [String],[Exp],String)]
getMethods = (map methodsDetails) . (getMethodDecl.getDecls.getClassBody)

-------------------------
-- Auxiliary Functions --
-------------------------

methodsDetails :: MemberDecl -> (String, String, [String],[Exp],String)
methodsDetails (MethodDecl mods _ Nothing (Ident mn) args _ body)   = ("void",mn,map prettyPrint args, getMethodsInvocation body,getModifier $ map prettyPrint mods)
methodsDetails (MethodDecl mods _ (Just rt) (Ident mn) args _ body) = (prettyPrint rt,mn,map prettyPrint args, getMethodsInvocation body,getModifier $ map prettyPrint mods)

--
--Gets all method invocations within a method definition
--
getMethodsInvocation :: MethodBody -> [Exp]
getMethodsInvocation (MethodBody Nothing)           = []
getMethodsInvocation (MethodBody (Just (Block []))) = []
getMethodsInvocation (MethodBody (Just (Block bs))) = concatMap getMIBlockRec bs


getMIBlockRec :: BlockStmt -> [Exp]
getMIBlockRec (BlockStmt stm)          = getMIStmRec stm
getMIBlockRec (LocalClass _)           = []
getMIBlockRec (LocalVars _ _ vdecls)   = concatMap getMIVarDeclRec vdecls

getMIStmRec :: Stmt -> [Exp]
getMIStmRec (StmtBlock (Block block))       = concatMap getMIBlockRec block
getMIStmRec (IfThen exp stm)                = getMIExp exp ++ getMIStmRec stm
getMIStmRec (IfThenElse exp stm1 stm2)      = getMIExp exp ++ getMIStmRec stm1 ++ getMIStmRec stm2
getMIStmRec (While exp stm)                 = getMIExp exp ++ getMIStmRec stm
getMIStmRec (BasicFor _ _ _ stm)            = getMIStmRec stm
getMIStmRec (EnhancedFor _ _ _ exp stm)     = getMIExp exp ++ getMIStmRec stm
getMIStmRec Empty                           = []
getMIStmRec (ExpStmt exp)                   = getMIExp exp
getMIStmRec (Assert exp mexp)               = 
 case mexp of 
      Nothing   -> getMIExp exp
      Just exp' -> getMIExp exp ++ getMIExp exp'
getMIStmRec (Switch _ bstms)                = concatMap getMIBlockRec $ concatMap (\(SwitchBlock e bstm) -> bstm) bstms
getMIStmRec (Do stm _)                      = getMIStmRec stm
getMIStmRec (Break _)                       = []
getMIStmRec (Continue _)                    = []
getMIStmRec (Return mexp)                   =
 case mexp of 
      Nothing  -> []
      Just exp -> getMIExp exp
getMIStmRec (Synchronized _ (Block block))  = concatMap getMIBlockRec block
getMIStmRec (Throw exp)                     = getMIExp exp
getMIStmRec (Try (Block block) _ mblock)    = 
  case mblock of 
      Nothing             -> concatMap getMIBlockRec block
      Just (Block block') -> concatMap getMIBlockRec block ++ concatMap getMIBlockRec block'
getMIStmRec (Labeled _ stm)                 = getMIStmRec stm


getMIVarDeclRec :: VarDecl -> [Exp]
getMIVarDeclRec (VarDecl id Nothing)        = []
getMIVarDeclRec (VarDecl id (Just vinit))   = getMIVarInitRec vinit

getMIVarInitRec :: VarInit -> [Exp]
getMIVarInitRec (InitExp exp)               = getMIExp exp
getMIVarInitRec (InitArray (ArrayInit arr)) = concatMap getMIVarInitRec arr

getMIExp :: Exp -> [Exp]
getMIExp (InstanceCreation _ _ args _)         = concatMap getMIExp args
getMIExp (QualInstanceCreation exp _ _ args _) = getMIExp exp ++ concatMap getMIExp args
getMIExp (ArrayCreateInit _ _ (ArrayInit arr)) = concatMap getMIVarInitRec arr
getMIExp (MethodInv minv)    = [MethodInv minv]
getMIExp (PostIncrement exp) = getMIExp exp
getMIExp (PostDecrement exp) = getMIExp exp
getMIExp (PreIncrement exp)  = getMIExp exp
getMIExp (PreDecrement exp)  = getMIExp exp
getMIExp (PrePlus exp)       = getMIExp exp
getMIExp (PreMinus exp)      = getMIExp exp
getMIExp (PreBitCompl exp)   = getMIExp exp
getMIExp (PreNot exp)        = getMIExp exp
getMIExp (Cast _ exp)        = getMIExp exp
getMIExp (BinOp exp1 _ exp2) = getMIExp exp1 ++ getMIExp exp2 
getMIExp (InstanceOf exp _)  = getMIExp exp
getMIExp (Cond _ exp1 exp2)  = getMIExp exp1 ++ getMIExp exp2
getMIExp (Assign _ _ exp)    = getMIExp exp
getMIExp _                   = []
