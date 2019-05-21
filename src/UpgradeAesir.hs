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
                (iprop', [])  -> let ip = ipropID %~ (\id -> getIdIprop iprop') $ (initprop env)
                                 in chainExec modelp (initpropGet .~ iprop' $ model) (env { initprop = ip}) errs 3
                (iprop', err) -> let ip = ipropID %~ (\id -> getIdIprop iprop') $ (initprop env)
                                 in chainExec modelp (initpropGet .~ iprop' $ model) (env { initprop = ip}) (err:errs) 3
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
genModel (Abs.Model ctxt) =
 do ctxt' <- getCtxt ctxt TopLevel    
    return (Model ctxt')

-- Context --

--TODO: Fix to check whether the initial property is annotated in multiple scopes (forbid this)
getCtxt :: Abs.Context -> Scope -> UpgradeModel Context
getCtxt (Abs.Ctxt _ _ _ Abs.PropertiesNil Abs.ForeachesNil) _ = fail $ "Error: No properties were defined in section GLOBAL\n."
getCtxt (Abs.Ctxt Abs.VarNil Abs.ActEventsNil Abs.TriggersNil Abs.PropertiesNil foreaches@(Abs.ForeachesDef _ _ _)) TopLevel = getForeaches foreaches (Ctxt [] [] [] PNIL []) (InFor (ForId "TopLevel"))
getCtxt (Abs.Ctxt vars ies Abs.TriggersNil prop foreaches) scope =
 getCtxt (Abs.Ctxt vars ies (Abs.TriggersDef []) prop foreaches) scope
getCtxt (Abs.Ctxt vars ies trigs prop foreaches) scope =
 do vars' <- getVars vars
    trigs' <- getTriggers trigs scope []
    env <- get
    let prop' = getProperty prop (map tiTN (allTriggers env)) env scope
    let cns   = (initprop env) ^. ipropID
    let ies'  = getActEvents ies  
    case runWriter prop' of
         ((PNIL,env'),_)                    -> do put env'
                                                  getForeaches foreaches (Ctxt vars' ies' trigs' PNIL []) scope
         ((Property pname states trans props,env'),s) -> 
                  let aux    = [tr | tr <- (splitOnIdentifier "," (s ^. _1)), not (elem tr (map ((\x -> x ++ "?").show) ies'))]
                      trs    = (addComma.removeDuplicates) aux
                      s'     = if (not.null) trs
                               then "Error: Trigger(s) [" ++ trs ++ "] is(are) used in the transitions, but is(are) not defined in section TRIGGERS.\n" 
                                     ++ s ^. _2 ++ s ^. _3 ++ s ^. _4
                               else s ^. _2 ++ s ^. _3 ++ s ^. _4
                  in if (null s')
                     then do put env' 
                             getForeaches foreaches (Ctxt vars' ies' trigs' (Property pname states trans props) []) scope
                     else fail s'

---
-- Variables --
---

getVars :: Abs.Variables -> UpgradeModel Variables
getVars Abs.VarNil        = return []
getVars (Abs.VarDef vars) = sequence $ map getVariable vars

getVariable :: Abs.Variable -> UpgradeModel Variable
getVariable (Abs.Var varm t vdecls) =
 let varm' = getVarModif varm
     t'    = getTypeAbs t
     vs    = map getVarDecl vdecls
 in do env <- get
       put env { varsInModel = Var varm' t' vs:varsInModel env}
       return $ Var varm' t' vs

getVarModif :: Abs.VarModifier -> VarModifier
getVarModif Abs.VarModifierFinal = VarModifierFinal
getVarModif Abs.VarModifierNil   = VarModifierNil

getVarDecl :: Abs.VarDecl -> VarDecl
getVarDecl (Abs.VarDecl id varinit) = VarDecl (getIdAbs id) (getVarInitAbs varinit)

---
-- ActEvents --
---

getActEvents :: Abs.ActEvents -> ActEvents
getActEvents Abs.ActEventsNil       = []
getActEvents (Abs.ActEventsDef ies) = map (\(Abs.ActEvent ie) -> ActEvent (getIdAbs ie)) ies

---
-- Triggers --
---

getTriggers :: Abs.Triggers -> Scope -> [Args] -> UpgradeModel Triggers
getTriggers Abs.TriggersNil _ _             = return []
getTriggers (Abs.TriggersDef es) scope args =
 do env <- get
    let xs = map (\ tr -> getTrigger' scope tr args) es
    let (ls, rs) = partitionErr (map (\e -> CM.evalStateT e env) xs)
    if (null ls)
    then sequence xs
    else fail $ foldr joinBad "" ls

--TODO: Update with overloading generation if Hoare triples are added to the model language
getTrigger' :: Scope -> Abs.Trigger -> [Args] -> UpgradeModel TriggerDef
getTrigger' scope (Abs.Trigger id binds ce wc) args =
 do env  <- get
    let id'' = getIdAbs id
    let xs   = [ x | x <- allTriggers env, id'' == tiTN x, tiScope x == scope ]
    let err  = if (not.null) xs
               then "Error: Multiple definitions for trigger " 
                    ++ id'' ++ ".\n" ++ show scope ++ "\n" 
               else ""
    let (bs, s) = runWriter $ getBindsArgs binds
    let err0    = if (not.null) s 
                  then err ++ "Error: Trigger declaration [" ++ id'' 
                       ++ "] uses wrong argument(s) [" ++ s ++ "].\n"
                  else err
    let (ce',s') = runWriter (getCompTriggers ce)
    let err1 = if (not.null) s'
               then err0 ++ ("Error: Trigger declaration [" ++ id'' 
                    ++ "] uses wrong argument(s) [" ++ s' ++ "] in the method component.\n")
               else err0
    let argss = map getIdBind bs
    case ce' of
         NormalEvent (BindingVar bind) mn args'
            -> let allArgs = map getIdBind (filter (\ c -> not (isBindStar c)) args') in
               let id  = getIdBind bind
                   wc' = getWhereClause wc
                   wcs = [x | x <- argss, not(elem x allArgs)]
                   vs  = filter (\ x -> x /= id) $ checkVarsInitialisation wcs (getVarsWC wc)
               in if ((not.null) vs) 
                  then fail $ err1 ++ "Error: Missing Initialization of variable(s) " 
                              ++ show vs ++  " in trigger declaration [" ++ id'' ++ "].\n"
                  else do let (b,zs)   = runWriter ((checkAllArgs argss allArgs bind))
                          let (b',s'') = runWriter (checkSpecialCases b mn bind bs [] zs id'' env scope)
                          if b' 
                          then if (not.null) err1 
                               then fail err1 
                               else do (ci,cinm) <- getClassVarName id'' mn bs bind s'' scope args
                                       let tr = TriggerDef { _tName = id''
                                                           , _args  = bs
                                                           , _compTrigger = ce'
                                                           , _whereClause = getWhereClause wc
                                                           }
                                       let ti = TI id'' mn ci cinm bs (Just tr) scope
                                       put env { allTriggers = ti : allTriggers env }
                                       return tr
                          else fail (err1 ++ s'')
         _  -> if (not.null) err1 then fail err1 else
               do put env { allTriggers = TI id'' "" "" "" bs Nothing scope: allTriggers env }
                  return TriggerDef { _tName = id''
                                    , _args  = bs
                                    , _compTrigger = ce'
                                    , _whereClause = getWhereClause wc
                                    }

isBindStar :: Bind -> Bool
isBindStar BindStar     = True
isBindStar BindStarExec = True
isBindStar BindStarCall = True
isBindStar _            = False

--Method handling the special cases of the use of new and channels
checkSpecialCases :: Bool -> MethodName -> Bind -> [Bind] -> [Bind] -> [String] -> Trigger -> Env -> Scope -> Writer String Bool
checkSpecialCases b mn bind bs rs zs id env scope = 
 if b
 then return b
 else case runWriter (checkMNforNew mn bind bs rs id zs) of
           (True,_)  -> return True
           (False,s) -> if null s
                        then case runWriter (checkForChannel bind env) of
                                  (True,s)  -> writer (True,s)
                                  (False,s) -> if tempScope scope
                                               then writer (True,s)
                                               else writer (False, "Error: Trigger declaration [" ++ id ++ "] uses wrong argument(s) [" 
                                                           ++ addComma zs ++ "] in the method component.\n")
                        else writer (False, s)

--Method handling new
checkMNforNew :: MethodName -> Bind -> [Bind] -> [Bind] -> Trigger ->  [String] -> Writer String Bool
checkMNforNew mn bind bs rs id zs = 
 case bind of
      BindId id -> if (mn /= "new")
                   then return False
                   else if null rs
                        then writer (False,"Error: new cannot be associated to an entry trigger.\n")
                        else if elem (BindType id (getIdBind (head rs))) bs
                             then if null zs 
                                  then return True
                                  else writer (False, "Error: Trigger declaration [" ++ id 
                                                      ++ "] uses wrong argument(s) [" ++ addComma zs 
                                                      ++ "] in the method component.\n")
                             else writer (False, "Error: Wrong exit object in trigger " ++ id ++ "\n.")
      _         -> return False

--Method handling channels
checkForChannel :: Bind -> Env -> Writer String Bool
checkForChannel bind env = 
 case bind of
      BindId id -> let vars = map varDecId $ concatMap getVarDeclVar 
                              $ filter (\v -> getTypeVar v == "Channel") $ varsInModel env
                   in if elem id vars
                      then writer (True,id)
                      else return False
      _         -> return False

properBind :: Bind -> [Bind]
properBind (BindType t id) = [BindType t id]
properBind _               = []

checkAllArgs :: [Id] -> [Id] -> Bind -> Writer [String] Bool
checkAllArgs argss allArgs bind =
 case bind of
      BindId id -> if (elem id argss)
                   then checkArgs argss allArgs
                   else case runWriter (checkArgs argss allArgs) of
                             (b,zs) -> writer (False,zs)
      _         -> checkArgs argss allArgs


checkArgs :: [Id] -> [Id] -> Writer [String] Bool
checkArgs _ []              = return True
checkArgs argss (a:allArgs) =
 do b <- checkArgs argss allArgs
    let s = if not(elem a argss) then [a] else []
    writer ((elem a argss && b),s)

checkRetVar :: [Bind] -> [Id] -> Bool
checkRetVar xs ids = case length xs of
                          0 -> True
                          1 -> elem (getIdBind (head xs)) ids
                          _ -> False

getVarsWC :: Abs.WhereClause -> [Id]
getVarsWC Abs.WhereClauseNil      = []
getVarsWC (Abs.WhereClauseDef xs) = map (\ (Abs.WhereExp bind _) -> (getIdBind.getBind_) bind) xs

checkVarsInitialisation :: [Id] -> [Id] -> [Id]
checkVarsInitialisation [] _      = []
checkVarsInitialisation (x:xs) wc = if (elem x wc)
                                    then checkVarsInitialisation xs wc
                                    else x:checkVarsInitialisation xs wc

getCompTrigger :: Abs.CompoundTrigger -> Writer String CompoundTrigger
getCompTrigger ce =
 case ce of
     Abs.NormalEvent (Abs.BindingVar bind) id binds ->
        case runWriter (getBindsBody (map getVarsAbs binds)) of
             (bs, s) -> do let id'  = getIdAbs id
                           tell s
                           return (NormalEvent (BindingVar (getBind_ bind)) id' bs)
     Abs.OnlyId id         -> do let id' = getIdAbs id
                                 return (OnlyId id')
     Abs.OnlyIdPar id      -> do let id' = getIdAbs id
                                 return (OnlyIdPar id')

getCompTriggers :: Abs.CompoundTrigger -> Writer String CompoundTrigger
getCompTriggers (Abs.Collection (Abs.CECollection esl wc)) = 
 do let xs = map getCEElement esl
    let wc' = getWhereClause wc
    ce <- sequence xs
    return (Collection (CECollection ce wc'))
getCompTriggers ce                                      = getCompTrigger ce

getCEElement :: Abs.CEElement -> Writer String CEElement
getCEElement (Abs.CEct ct)    = 
 case runWriter (getCompTrigger ct) of
      (ct',s) -> do tell s
                    return (CEct ct')
getCEElement (Abs.CEid id)    = 
 do let id' = getIdAbs id
    return (CEid id')
getCEElement (Abs.CEidpar id) = 
 do let id' = getIdAbs id
    return (CEidpar id')

--Checks if the arguments in the triggers have the right form
getBindsArgs :: [Abs.Bind] -> Writer String [Bind]
getBindsArgs []     = return []
getBindsArgs (b:bs) =
 case runWriter (getBindsArgs bs) of
      (bs', s) -> case b of
                       Abs.BindType t id -> do tell s
                                               return ((BindType (getTypeAbs t) (getIdAbs id)):bs')
                       _                 -> do tell (mAppend (printTree b) s)
                                               return bs'

--Checks if the arguments in the method call on a trigger have the right form
getBindsBody :: [Abs.Bind] -> Writer String [Bind]
getBindsBody []     = return []
getBindsBody (b:bs) =
 case runWriter (getBindsBody bs) of
      (xs, s) -> case b of
                       Abs.BindId id -> do tell s
                                           return ((BindId (getIdAbs id)):xs)
                       Abs.BindStar  -> do tell s
                                           return (BindStar:xs)
                       _             -> do tell (mAppend (printTree b) s)
                                           return xs

getBind_ :: Abs.Bind -> Bind
getBind_ Abs.BindStar            = BindStar
getBind_ (Abs.BindType t id)     = BindType (getTypeAbs t) (getIdAbs id)
getBind_ (Abs.BindId id)         = BindId (getIdAbs id)
getBind_ Abs.BindStarExec        = BindStarExec
getBind_ Abs.BindStarCall        = BindStarCall
getBind_ (Abs.BindTypeExec t id) = BindTypeExec (getTypeAbs t) (getIdAbs id)
getBind_ (Abs.BindTypeCall t id) = BindTypeCall (getTypeAbs t) (getIdAbs id)
getBind_ (Abs.BindIdExec id)     = BindIdExec (getIdAbs id)
getBind_ (Abs.BindIdCall id)     = BindIdCall (getIdAbs id)

-- Removes white spaces added by printTree after ';'
getWhereClause :: Abs.WhereClause -> WhereClause
getWhereClause Abs.WhereClauseNil        = ""
getWhereClause (Abs.WhereClauseDef wexp) = (concat.lines.printTree) wexp

--
-- Properties --
--

getProperty :: Abs.Properties -> [Id] -> Env -> Scope -> Writer (String,String,String,String) (Property,Env)
getProperty Abs.PropertiesNil _ env _                                               = return (PNIL,env)
getProperty (Abs.ProperiesDef id (Abs.PropKindNormal states trans) props) enms env scope =
 case runWriter (getTransitions (getIdAbs id) trans env scope) of
      ((t,env'),s') ->
           let ts      = map (trigger.arrow) t              
               xs      = [x | x <- ts, not (elem x enms)]
               pname   = getIdAbs id
               states' = getStates' states
               s''     = execWriter $ checkStatesWF states' pname t
               cns     = (initprop env) ^. ipropID
               (accep,n1)  = checkAllHTsExist (getAccepting states') 0 cns pname scope
               (bad,n2)    = checkAllHTsExist (getBad states') 0 cns pname scope
               (normal,n3) = checkAllHTsExist (getNormal states') 0 cns pname scope
               (start,n4)  = checkAllHTsExist (getStarting states') 0 cns pname scope
               ip     = multipleInitS (n1 + n2 + n3 + n4 - 1, pname)
               errs   = concat $ start ++ accep ++ bad ++ normal
               errs'  = errs ++ ip
            in if (n1 + n2 + n3 + n4 == 1)
               then if (alreadyAnnotatedIP (initprop env'))
                    then do let er = "Error: Initial property annotated in multiple properties: [" 
                                      ++ pname ++ ", " ++ (initprop env') ^. ipPropn ++ "].\n"
                            (p,env'') <- getProperty props enms env' scope
                            pass $ return ((), \s -> mkErrTuple s (addComma xs) s' s'' (errs' ++ er))
                            return (Property { pName        = pname
                                             , pStates      = states'
                                             , pTransitions = t
                                             , pProps       = p },env'')
                    else do let ip'   = ipScope %~ (const scope) $ (initprop env')
                            let ip''  = ipPropn %~ (const pname) $ ip'
                            let sts   = getAccepting states' ++ getStarting states' 
                                        ++ getBad states' ++ getNormal states'
                            let name = annotatedState sts
                            let ip''' = ipStn %~ (const name) $ ip''
                            let env'' = env' { initprop = ip''' }
                            (p,env''') <- getProperty props enms env'' scope
                            pass $ return ((), \s -> mkErrTuple s (addComma xs) s' s'' errs')
                            return (Property { pName        = pname
                                             , pStates      = states'
                                             , pTransitions = t
                                             , pProps       = p },env''')
               else do (p,env'') <- getProperty props enms env' scope
                       pass $ return ((), \s -> mkErrTuple s (addComma xs) s' s'' errs')
                       return (Property { pName        = pname
                                        , pStates      = states'
                                        , pTransitions = t
                                        , pProps       = p },env'')

getStates' :: Abs.States -> States
getStates' (Abs.States start accep bad norm) = States { getStarting = getStarting' start
                                                      , getAccepting = getAccepting' accep 
                                                      , getBad = getBad' bad
                                                      , getNormal = getNormal' norm
                                                      }

getAccepting' :: Abs.Accepting -> Accepting
getAccepting' Abs.AcceptingNil      = []
getAccepting' (Abs.AcceptingDef ss) = map getState ss

getBad' :: Abs.Bad -> Bad
getBad' Abs.BadNil      = []
getBad' (Abs.BadDef ss) = map getState ss

getNormal' :: Abs.Normal -> Normal
getNormal' Abs.NormalNil      = []
getNormal' (Abs.NormalDef ss) = map getState ss

getStarting' :: Abs.Starting -> Starting
getStarting' (Abs.StartingDef ss) = map getState ss

getState :: Abs.State -> State
getState (Abs.State (Abs.NameState id) ic Abs.CNSNil)    = State (getIdAbs id) (getInitCode ic) []
getState (Abs.State (Abs.NameState id) ic (Abs.CNS cns)) = State (getIdAbs id) (getInitCode ic) (map (getIdAbs.getConstNameAbs) cns)

getInitCode :: Abs.InitialCode -> InitialCode
getInitCode Abs.InitNil      = InitNil
getInitCode (Abs.InitProg p) = InitProg (getJava p)

--Check if the states are well-formed
checkStatesWF :: States -> PropertyName -> Transitions -> Writer String ()
checkStatesWF sts pn trans =
 do oneStarting sts pn
    stateTransE trans sts pn
    uniqueNamesStates sts pn

--Checks if there is one (and only one) starting state
oneStarting :: States -> PropertyName -> Writer String ()
oneStarting sts pn = 
 case length (getStarting sts) of
      0 -> tell ("Error: There is no starting state " ++ "in property " ++ pn ++ ".\n")
      1 -> return ()
      otherwise -> tell ("Error: There is more than one starting state " ++ "in property " ++ pn ++ ".\n")

--Checks if all the states used in the transitions exist
stateTransE :: Transitions -> States -> PropertyName -> Writer String ()
stateTransE trans sts pn = 
 let all  = map (^. getNS) $ allStates sts
     stsT = concatMap (\ t -> [fromState t,toState t]) trans
     xs   = [y | y <- stsT , not (elem y all)]
 in if null xs
    then return ()
    else tell (msg xs) 
               where msg xs = if length xs > 1
                              then "Error: In property " ++ pn 
                                   ++ ", the following state names used in the transitions do not exist: " 
                                   ++ show xs ++ ".\n"
                              else "Error: In property " ++ pn
                                   ++ ", the following state name used in the transitions do not exist: "
                                   ++ show xs ++ ".\n"

--Checks if the names of the states are unique.
uniqueNamesStates :: States -> PropertyName -> Writer String ()
uniqueNamesStates sts pn = 
 let all = uniqueNames $ allStates sts
 in if null all
    then return ()
    else tell (msg all) 
               where msg xs = if length xs > 1
                              then "Error: In property " ++ pn
                                   ++ ", the following state names are not unique: " ++ show xs ++ ".\n"
                              else "Error: In property " ++ pn
                                   ++ ", the following state name is not unique: " ++ show xs ++ ".\n"

allStates :: States -> [State]
allStates sts =
 let accp = getAccepting sts
     bad  = getBad sts
     norm = getNormal sts
     star = getStarting sts
 in star ++ accp ++ bad ++ norm

uniqueNames :: [State] -> [NameState]
uniqueNames sts = removeDuplicates $ map (^.getNS) $ sameNameStates sts

sameNameStates :: [State] -> [State]
sameNameStates []     = []
sameNameStates (x:xs) = getSameNameStates x xs ++ sameNameStates xs

getSameNameStates :: State -> [State] -> [State]
getSameNameStates st []     = []
getSameNameStates st (x:xs) = 
 if (stateEq st x)
 then x:getSameNameStates st xs
 else getSameNameStates st xs

stateEq :: State -> State -> Bool
stateEq st st' = st == st' || st ^. getNS == st' ^. getNS

getTransitions :: PropertyName -> Abs.Transitions -> Env -> Scope -> Writer String (Transitions,Env)
getTransitions id (Abs.Transitions ts) env scope = 
 do xs <- sequence $ map (getTransition' id env scope) ts
    let trans = map fst xs
    let envs  = map snd xs
    let env'  = joinEnvsCreate envs emptyEnv
    return (trans,env')

getTransition' :: PropertyName -> Env -> Scope -> Abs.Transition -> Writer String (Transition,Env)
getTransition' id env scope (Abs.Transition (Abs.NameState q1) (Abs.NameState q2) ar) = 
 case runWriter (getArrow ar env scope) of
      ((xs,env'),s) -> 
          do let err = "Error: Parsing error in an action of a transition from state " 
                        ++ getIdAbs q1 ++ " to state " 
                        ++ getIdAbs q2 ++ " in property " ++ id ++ ".\n"
             let s' = if null s then "" else err ++ s
             tell s'                  
             return (Transition { fromState = getIdAbs q1
                                , arrow = xs
                                , toState = getIdAbs q2
                                },env')

getArrow :: Abs.Arrow -> Env -> Scope -> Writer String (Arrow,Env)
getArrow (Abs.Arrow id mark Abs.Cond1) env scope        = 
 return $ (Arrow { trigger = getIdAbs id ++ addQuestionMark mark, cond = "", action = "" },env)
getArrow (Abs.Arrow id mark (Abs.Cond2 cond)) env scope = 
 case cond of
      Abs.CondExpDef cexp     -> return $ (Arrow { trigger = getIdAbs id ++ addQuestionMark mark, cond = printTree cexp, action = "" },env)
      Abs.CondAction cexp act -> 
        let act' = (trim.printTree) act in
        case ParAct.parse act' of 
             Bad s -> do tell s
                         return $ (Arrow { trigger = getIdAbs id ++ addQuestionMark mark, cond = printTree cexp, action = "Parse error" },env)
             Ok (Act.Actions ac) -> 
                      case runWriter $ sequence (map (\a -> checkTempInCreate a env) ac) of
                           (ac',s') -> do tell s'
                                          let ac'' = filter isCreateAct ac'
                                          let acts = [CAI y z "" x scope | (x,(y,z)) <- zip ac'' (map getIdAndArgs ac'')]
                                          let env' = env { allCreateAct = acts ++ (allCreateAct env)}
                                          return $ (Arrow { trigger = getIdAbs id ++ addQuestionMark mark, cond = printTree cexp, action = act' },env')
      

isCreateAct :: Act.Action -> Bool
isCreateAct (Act.ActCreate _ _) = True
isCreateAct _                   = False

getIdAndArgs :: Act.Action -> (Id,[Act.Args])
getIdAndArgs (Act.ActCreate (Act.Temp (Act.IdAct id)) args) = (id,args)

joinEnvsCreate :: [Env] -> Env -> Env
joinEnvsCreate [] env          = env
joinEnvsCreate (env:envs) env' = joinEnvsCreate envs (join env env')
                                      where join env env' = env { allCreateAct = (allCreateAct env) ++ (allCreateAct env')}


addQuestionMark :: Abs.Actmark -> String
addQuestionMark Abs.ActMarkNil  = ""
addQuestionMark Abs.ActMark     = "?"
            
checkTempInCreate :: Act.Action -> Env -> Writer String Act.Action
checkTempInCreate ac@(Act.ActCreate (Act.Temp (Act.IdAct id) ) _) env = 
 let tmpids = map fst $ tempsInfo env
 in if not (elem id tmpids)
    then do tell $ "Template " ++ id ++ ", which is used in an action create does not exist.\n"
            return ac
    else return ac
checkTempInCreate (Act.ActCond conds act) env = 
 case runWriter $ checkTempInCreate act env of
      (ac,s) -> do tell s
                   return $ Act.ActCond conds ac
checkTempInCreate (Act.ActBlock (Act.Actions acts)) env     = 
 case runWriter $ sequence $ map (\act -> checkTempInCreate act env) acts of
      (ac,s) -> do tell s
                   return $ Act.ActBlock (Act.Actions ac)
checkTempInCreate act env                     = return act

---------------
-- Foreaches --
---------------

getForeaches :: Abs.Foreaches -> Context -> Scope -> UpgradeModel Context
getForeaches Abs.ForeachesNil ctxt _ = 
 do env <- get    
    put env { actes = actes env ++ map show (ctxt ^. actevents)} 
    return ctxt
getForeaches (Abs.ForeachesDef _ (Abs.Ctxt _ _ _ _ (Abs.ForeachesDef args actxt fors)) afors) _ _ = 
 fail "Error: StaRVOOrS does not support nested Foreaches.\n"
getForeaches afors@(Abs.ForeachesDef _ (Abs.Ctxt _ _ _ _ Abs.ForeachesNil) _) ctxt scope = 
 let afors' = prepareForeaches afors
 in do env <- get
       put env { actes = actes env ++ map show (ctxt ^. actevents)}
       fors <- sequence $ map (uncurry getForeach) (zip afors' (createIds scope afors'))
       env' <- get
       return (foreaches .~ fors $ ctxt)

prepareForeaches :: Abs.Foreaches -> [Abs.Foreaches]
prepareForeaches Abs.ForeachesNil                  = []
prepareForeaches (Abs.ForeachesDef args ctxt fors) = 
 (Abs.ForeachesDef args ctxt Abs.ForeachesNil):prepareForeaches fors

createIds :: Scope -> [Abs.Foreaches] -> [ForId]
createIds TopLevel afors          = map (ForId . show) [1..length afors]
createIds (InFor (ForId s)) afors = 
 if s == "TopLevel" 
 then [ForId s]
 else map (ForId . (s++) . show) [1..length afors]

getForeach :: Abs.Foreaches -> ForId -> UpgradeModel Foreach
getForeach (Abs.ForeachesDef args ctxt Abs.ForeachesNil) id = 
 do ctxt' <- getCtxt ctxt (InFor id)
    env <- get    
    case ctxt' ^. foreaches of
      [] -> do let args'     = map getArgs args
               let propn     = pName $ ctxt' ^. property
               let Args t cl = head $ args'               
               put env { propInForeach = (propn,t,cl):propInForeach env }               
               return $ Foreach args' ctxt' id
      _  -> fail $ "Error: StaRVOOrS does not support nested Foreaches.\n"


---------------
-- Templates --
---------------

genTemplates :: Abs.Templates -> UpgradeModel Templates
genTemplates Abs.TempsNil   = return TempNil
genTemplates (Abs.Temps xs) = 
 do xs <- sequence $ map genTemplate xs
    env <- get
    put env { tempsInfo = tempsInfo env ++ foldr (\ x xs -> (x ^. tempId, x ^. tempBinds) : xs) [] xs}
    return $ Temp xs 

--TODO: If templates added to the model, modify to check whether initial prop is not annotated in
--multiple scopes, and add the scope to the initprop component if the initial prop is only annotated in a template
genTemplate :: Abs.Template -> UpgradeModel Template
genTemplate (Abs.Temp id args (Abs.Body vars ies trs prop)) = 
 do args' <- hasReferenceType (map ((uncurry makeArgs).getArgsAbs) args) (getIdAbs id)
    trigs' <- getTriggers trs (InTemp (getIdAbs id)) args'
    env <- get
    let cns   = (initprop env) ^. ipropID
    let prop' = getProperty prop (map (^. tName) trigs') env (InTemp (getIdAbs id))
    case runWriter prop' of
         ((PNIL,env'),_)                      -> fail $ "Error: The template " ++ getIdAbs id 
                                                        ++ " does not have a PROPERTY section.\n"
         ((Property pname states trans props, env'), s) -> 
                  let s'      = s ^. _2 ++ s ^. _3 ++ s ^. _4
                                ++ if props /= PNIL 
                                   then "Error: In template " ++ getIdAbs id 
                                        ++ ", it should describe only one property.\n"
                                   else ""
                      temptrs = splitOnIdentifier "," $ s ^. _1
                  in if ((not.null) s')
                     then fail s'
                     else do put env' { actes = actes env' ++ map show (getActEvents ies)}
                             return $ Template { _tempId        = getIdAbs id
                                               , _tempBinds     = args'
                                               , _tempVars      = getValue $ getVars vars
                                               , _tempActEvents = getActEvents ies
                                               , _tempTriggers  = trigs'
                                               , _tempProp      = Property pname states trans props
                                               }

hasReferenceType :: [Args] -> String -> UpgradeModel [Args]
hasReferenceType xs id = 
 case filterRefTypes xs of
      [] -> fail $ "Error: The template " ++ id ++ " does not have any reference type as argument.\n"
      _  -> return xs

--Check for the arguments used in the create actions
wellFormedActions :: UpgradeModel CModel -> String
wellFormedActions model = 
 let env = getEnvVal model in
 case runWriter $ sequence $ map (wellFormedAction env) (allCreateAct env) of
      (b,s) -> if and b
               then ""
               else s 

wellFormedAction:: Env -> CreateActInfo -> Writer String Bool
wellFormedAction env cai = 
 let xs = [ tmp | tmp <- tempsInfo env, fst tmp == (cai ^. caiId)]
 in if null xs
    then writer (False, "Error: In an action create, the template " ++ cai ^. caiId ++ " does not exist.\n")
    else let tempArgs = snd $ head $ xs
             ys       = splitTempArgs (zip tempArgs (cai ^. caiArgs)) emptyTargs
         in if length tempArgs /= length (cai ^. caiArgs)
            then writer (False, "Error: In an action create, the amount of arguments does not match the arguments in template "
                                ++ cai ^. caiId ++ ".\n")
            else case runWriter $ checkTempArgs ys env (cai ^. caiScope) of
                      (xs,s) -> if and xs
                                then return True
                                else writer (False,s)

splitTempArgs :: [(Args,Act.Args)] -> TempArgs -> TempArgs
splitTempArgs [] targs         = targs
splitTempArgs (arg:args) targs = 
 case getArgsType (fst arg) of
      "Action"     -> splitTempArgs args (targs {targAct = arg : targAct targs})
      "Condition"  -> splitTempArgs args (targs {targCond = arg : targCond targs})
      "Trigger"    -> splitTempArgs args (targs {targTr = arg : targTr targs})
      "MethodName" -> splitTempArgs args (targs {targMN = arg : targMN targs})
      _            -> splitTempArgs args (targs {targRef = arg : targRef targs})

--TODO: Update if Hoare triples are added to the model
checkTempArgs :: TempArgs -> Env -> Scope -> Writer String [Bool]
checkTempArgs targs env scope = 
 sequence [ checkTempArgsActions (map snd $ targAct targs)
          , checkTempArgsConditions (map snd $ targCond targs)
          , checkTempArgsTriggers (map snd $ targTr targs) (allTriggers env) scope
          , checkMethodNames (map snd $ targMN targs) (javaFilesInfo env)
          ]

checkTempArgsActions :: [Act.Args] -> Writer String Bool
checkTempArgsActions []    = return True
checkTempArgsActions targs = 
 let (xs,ys) = partitionErr $ map (ParAct.parse . (\xs -> xs ++ ";") . showActArgs) targs
 in if null xs 
    then return True
    else writer (False, "Error: In an action create: " ++ (unlines $ map fromBad xs))

showActArgs :: Act.Args -> String
showActArgs (Act.ArgsId (Act.IdAct id))                        = id
showActArgs (Act.ArgsS s)                                      = s
showActArgs (Act.ArgsNew (Act.Prog (Act.IdAct id) args inner)) = "new " ++ id ++ PrintAct.printTree args ++ PrintAct.printTree inner
showActArgs act                                                = PrintAct.printTree act

checkTempArgsConditions :: [Act.Args] -> Writer String Bool 
checkTempArgsConditions targs = 
 let (xs,ys) = partitionErr $ map (ParJML.parse . showActArgs) targs
 in if null xs 
    then return True
    else writer (False, "Error: In an action create, syntax error(s) on the condition(s) [" ++ addComma (map fromBad xs) ++ "].\n")

checkTempArgsTriggers :: [Act.Args] -> [TriggersInfo] -> Scope -> Writer String Bool
checkTempArgsTriggers targs tinfs scope = 
 let xs = [ tr | tr <- map showActArgs targs, tinf <- tinfs, tiScope tinf == scope, tiTN tinf == tr]
 in if length xs == length targs
    then return True 
    else writer (False, "Error: In an action create, the trigger(s) [" ++ addComma xs ++ "] do(es) not exist.\n") 

checkMethodNames :: [Act.Args] -> [(String, ClassInfo, JavaFilesInfo)] -> Writer String Bool
checkMethodNames targs minfs =
 let xs = removeDuplicates [ mn | mn <- map showActArgs targs, xs <- minfs, mn' <- methodsInFiles (xs ^. _3), mn == (mn' ^. _2) ]
 in if length xs == length targs
    then return True 
    else writer (False, "Error: In an action create, the method(s) [" 
                        ++ addComma [ x | x <- map showActArgs targs, not (elem x xs)] ++ "] do(es) not exist.\n") 


-----------------
-- CInvariants --
-----------------

genClassInvariants :: Abs.CInvariants -> UpgradeModel CInvariants
genClassInvariants absinvs =
 case runWriter (genClassInvariants' absinvs) of
      (cinvs,s) -> if null s
                   then return cinvs
                   else fail s

genClassInvariants' :: Abs.CInvariants -> Writer String CInvariants
genClassInvariants' Abs.CInvempty           = return []
genClassInvariants' (Abs.CInvariants cinvs) = sequence $ map getCInv cinvs

getCInv :: Abs.CInvariant -> Writer String CInvariant
getCInv (Abs.CI cn jml) = 
 case runWriter (getJML jml "") of
      (jml',s) -> if null s 
                  then return $ CI (getIdAbs cn) jml'
                  else do tell $ "Error: Parse on error on class invariant [" ++ printTree jml ++ "] for the class " ++ getIdAbs cn ++ ".\n"
                          return CInvNil

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
      Bad s -> do tell $ "Error: JML syntax error on the " ++ str
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

mAppend :: String -> String -> String
mAppend [] []     = ""
mAppend [] (y:ys) = y:ys
mAppend (x:xs) [] = x:xs
mAppend xs ys     = xs ++ "," ++ ys

checkAllHTsExist :: [State] -> Int -> Id -> PropertyName -> Scope -> ([String],Int)
checkAllHTsExist [] n _ _ _            = ([],n)
checkAllHTsExist (s:ss) n "" pn scope  = error $ "Error: Initial property name component is empty.\n"
checkAllHTsExist (s:ss) n cns pn scope = 
 let ns   = s ^. getNS
     cns' = s ^. getCNList
     aux  = [x | x <- cns' , not (x == cns)]
     n'   = length [x | x <- cns' , x == cns]
 in if (null aux)-- TODO: add '|| (tempScope scope))' if Hoare triples added to the model
    then (a,b + n')
    else (("Error: On property " ++ pn
         ++ ", in state " ++ ns ++ ", the initial property ["
         ++ addComma aux
         ++ "] do(es) not exist.\n") : a ,b + n')
                              where (a,b) = checkAllHTsExist ss n cns pn scope 

multipleInitS :: (Int, String) -> String
multipleInitS (0,_)            = ""
multipleInitS (n, str) | n > 0 = "Error: Initial property annotated in multiple states in property " ++ str ++ ".\n"
multipleInitS (n, str) | n < 0 = ""

mkErrTuple :: (String, String,String,String) -> String -> String -> String -> String -> (String,String,String,String)
mkErrTuple s xs s' s'' s''' = ((mAppend xs (s ^. _1)), s' ++ s ^. _2, s ^. _3 ++ s'', s ^. _4 ++ s''')

alreadyAnnotatedIP :: IPropInfo -> Bool
alreadyAnnotatedIP ip = 
 let propn = ip ^. ipPropn 
     scope = ip ^. ipScope
     names = ip ^. ipStn
 in not (null propn && scope == TopLevel && null names)

annotatedState :: [State] -> String
annotatedState []     = ""
annotatedState (s:ss) = 
 if ((not.null) (s ^. getCNList))
 then s ^. getNS
 else annotatedState ss

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
 , initprop        :: IPropInfo 
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
               , initprop        = ipInfoEmpty
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

get = CM.get
put = CM.put
runStateT = CM.runStateT

getValue :: UpgradeModel a -> a
getValue uppd = fst . fromOK $ runStateT uppd emptyEnv

getEnvVal :: UpgradeModel a -> Env
getEnvVal uppd = snd . fromOK $ runStateT uppd emptyEnv

