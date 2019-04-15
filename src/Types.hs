{-# LANGUAGE TemplateHaskell #-}

module Types where

import qualified Data.Map as Map
import System.FilePath
import System.Console.GetOpt
import Data.Maybe ( fromMaybe )
import Language.Java.Syntax hiding(Type,VarDecl,Modifier)
import qualified ParserActions.AbsActions as Act
import Control.Lens hiding(Context)
import Data.List (intercalate)

------------
-- ppDATE --
------------

data CModel = CModel
  { _importsGet     :: Imports
  , _modelGet       :: Model
  , _templatesGet   :: Templates
  , _cinvariantsGet :: CInvariants
  , _initpropGet    :: IProp
  , _methodsGet     :: Methods 
  } deriving (Show, Eq)

data Import = Import String deriving (Eq)

instance Show Import where
 show (Import imp) = "import " ++ imp ++ " ;"

type Imports = [Import]

type Class = String
type ClassInfo = String
type BodyCInv = String

data CInvariant = CI Class BodyCInv | CInvNil deriving (Eq)

instance Show CInvariant where
 show (CI cl body) = cl ++ " {" ++ (concat.lines) body ++ "}"
 show CInvNil      = ""

type CInvariants = [CInvariant]

type HTName     = String
type MethodName = String

----------------------
-- Initial Property --
----------------------

data IProp = IProp Id JMLExp deriving(Eq,Show)

getIdIprop :: IProp -> Id
getIdIprop (IProp id _) = id 

-----------
-- Model --
-----------

data Context =
   Ctxt { _variables :: Variables
        , _actevents :: ActEvents
        , _triggers  :: Triggers
        , _property  :: Property
        , _foreaches :: Foreaches
        }
  deriving (Eq,Show,Read)

data Model = Model { _ctxtGet  :: Context } deriving (Show, Eq)

---------------
-- Templates --
---------------

data Templates = TempNil | Temp [Template] deriving (Eq,Show)

data Template = Template
  { _tempId        :: Id
  , _tempBinds     :: [Args]
  , _tempVars      :: Variables
  , _tempActEvents :: ActEvents
  , _tempTriggers  :: Triggers 
  , _tempProp      :: Property
  } deriving (Show, Eq)

data TempArgs = TArgs --Arguments used to instantiate a template
 { targTr   :: [(Args,Act.Args)]--triggers
 , targAct  :: [(Args,Act.Args)]--actions
 , targCond :: [(Args,Act.Args)]--conditions
 , targHT   :: [(Args,Act.Args)]--Hoare triples
 , targRef  :: [(Args,Act.Args)]--reference types
 , targMN   :: [(Args,Act.Args)]--method names
 } deriving (Show,Eq)

emptyTargs :: TempArgs
emptyTargs = TArgs [] [] [] [] [] []

--------------
-- Methods  --
--------------

type Methods = String

---------------
-- Foreaches --
---------------

type Foreaches = [Foreach]

--ForId is introduced to keep track of the scope where a trigger is defined
data Foreach = 
 Foreach { _getArgsForeach :: [Args]
         , _getCtxtForeach :: Context
         , _getIdForeach :: ForId 
         } deriving (Eq,Show, Read)

data ForId = ForId Id deriving (Eq,Read)

instance Show ForId where
 show (ForId id) = id

--Type used to know where a trigger is defined
data Scope = TopLevel | InFor ForId | InTemp Id deriving (Eq,Show,Read)

tempScope :: Scope -> Bool
tempScope (InTemp _) = True
tempScope _          = False

data Args =
 Args { getArgsType :: Type
      , getArgsId :: Id
      } deriving (Eq,Ord,Read)

instance Show Args where
 show (Args t id) = t ++ " " ++ id

makeArgs :: Type -> Id -> Args
makeArgs t id = Args t id

bindToArgs :: Bind -> Args
bindToArgs (BindType t id) = Args t id
bindToArgs _               = error "bindToArgs.\n"

---------------
-- Variables --
---------------

type Variables = [Variable]

data Variable = 
 Var { getVarMod     :: VarModifier
     , getTypeVar    :: Type
     , getVarDeclVar :: [VarDecl]
     } deriving (Eq,Ord,Read)

instance Show Variable where
 show (Var modif t vdecls) = show modif ++ t ++ " " ++ intercalate "," (map show vdecls) ++ " ;"

data VarModifier =
   VarModifierFinal
 | VarModifierNil
  deriving (Eq,Ord,Read)

instance Show VarModifier where
 show VarModifierFinal = "final "
 show VarModifierNil   = ""

data VarDecl =
 VarDecl { varDecId   :: Id
         , varDecInit :: VariableInitializer
         } deriving (Eq,Ord,Read)

instance Show VarDecl where
 show (VarDecl id varinit) = id ++ show varinit

data VariableInitializer =
   VarInit VarExp
 | VarInitNil
  deriving (Eq,Ord,Read)

instance Show VariableInitializer where
 show VarInitNil    = ""
 show (VarInit exp) = " = " ++ exp 

getVariableArgs :: Variable -> [Args]
getVariableArgs (Var vm t [])          = []
getVariableArgs (Var vm t (dec:decls)) = Args t (getVarDeclId dec) : getVariableArgs (Var vm t decls)

getVarDeclId :: VarDecl -> Id
getVarDeclId (VarDecl id _) = id

------------------
-- Useful types --
------------------

type Id = String

type Type = String

type VarExp = String

type XML = String

type JPath = String

type Java = String

type Filename = String

type ErrorMsg = String

type JMLExp = String

type MethodInvocations = [Exp]

type Channel = String

data TriggersInfo = 
 TI { tiTN      :: Trigger --trigger_name
    , tiMN      :: MethodName --method_name
    , tiCI      :: ClassInfo --class_type
    , tiCVar    :: String --class_variable_name
    , tiBinds   :: [Bind]
    , tiTrDef   :: Maybe TriggerDef
    , tiScope   :: Scope
    } deriving (Show,Eq)

data CreateActInfo = 
 CAI { _caiId    :: Id
     , _caiArgs  :: [Act.Args]
     , _caiCh    :: Channel
     , _caiAct   :: Act.Action
     , _caiScope :: Scope
     } deriving (Show,Eq)

--------------
-- PROPERTY --
--------------

data InitialCode =
   InitNil
 | InitProg Java
  deriving (Eq,Ord,Read)

instance Show InitialCode where
 show InitNil         = ""
 show (InitProg java) = " { " ++ java ++ " } " 

type PropertyName = String
type NameState = String

data State = State 
 {_getNS :: NameState 
 ,_getInitialCode :: InitialCode
 ,_getCNList :: [HTName]}
   deriving (Eq,Read)

instance Show State where
 show (State _ns _initc _hts) = _ns ++ show _initc ++ foo _hts ++ "; "
                                 where foo []  = ""
                                       foo hts = " (" ++ intercalate "," hts ++ ") "

type Accepting = [State]
type Bad = [State]
type Normal = [State]
type Starting = [State]

data States = States 
  { getStarting  :: Starting
  , getAccepting :: Accepting
  , getBad       :: Bad
  , getNormal    :: Normal   
  } deriving (Eq, Show,Read)

type Transitions = [Transition]

type Trigger = String
type Cond    = String
type Action  = String

data Arrow = Arrow 
  { trigger :: Trigger
  , cond    :: Cond
  , action  :: Action
  } deriving (Eq,Read)

instance Show Arrow where
 show (Arrow tr c act) = " [" ++ tr ++ " \\ "  ++ c ++ " \\ " ++ (concat.lines) act ++ " ]"

data Transition = Transition 
  { fromState :: NameState
  , arrow :: Arrow
  , toState :: NameState
  } deriving (Eq,Read)

instance Show Transition where
 show (Transition fns arr tns) = fns ++ " -> " ++ tns ++ show arr

data Property = Property
  { pName        :: PropertyName
  , pStates      :: States
  , pTransitions :: Transitions
  , pProps       :: Property
  } | PNIL 
         deriving (Show, Eq,Read)


---------------
-- ActEvents --
---------------

type ActEvents = [ActEvent]

data ActEvent =
   ActEvent Id
  deriving (Eq,Ord,Read)

instance Show ActEvent where
 show (ActEvent id) = id

--------------
-- Triggers --
--------------

type WhereClause = String

data TriggerDef = TriggerDef 
  { _tName :: Trigger
  , _args :: [Bind]
  , _compTrigger :: CompoundTrigger
  , _whereClause :: WhereClause
  } deriving (Eq,Read)

instance Show TriggerDef where 
 show (TriggerDef nm [] ct w) = nm ++ "() = { " ++ show ct ++ " }" ++ showWhere w
 show (TriggerDef nm xs ct w) = nm ++ "(" ++ intercalate "," (map show xs) ++ ") = { " ++ show ct ++ " }" ++ showWhere w

showWhere :: String -> String
showWhere [] = ""
showWhere xs = " where { " ++ xs ++ " }"

data CompoundTrigger =
   NormalEvent Binding Id [Bind]
 | OnlyId Id
 | OnlyIdPar Id
 | Collection TriggerList
  deriving (Eq,Read)

updCEne :: CompoundTrigger -> Binding -> CompoundTrigger
updCEne (NormalEvent bind id bs) bind' = NormalEvent bind' id bs

instance Show CompoundTrigger where
 show (NormalEvent b id binds) = show b ++ "." ++ id ++ "(" ++ intercalate "," (map show binds) ++ ")"
 show (OnlyId id)                 = id
 show (OnlyIdPar id)              = id ++ "()"
 show (Collection tls)            = show tls

getCTArgs :: CompoundTrigger -> [Bind]
getCTArgs (NormalEvent _ _ bs) = bs

data TriggerList =
   CECollection [CEElement] WhereClause
  deriving (Eq,Read)

data CEElement =
   CEct CompoundTrigger
 | CEid Id
 | CEidpar Id
  deriving (Eq,Read)

instance Show CEElement where
 show (CEct ct)    = show ct
 show (CEid id)    = id
 show (CEidpar id) = id ++ "()"

instance Show TriggerList where
 show (CECollection xs wc) = foldr (\x xs -> "{" ++ x ++ "}" ++ " | " ++ xs) [] (map show xs)
                             ++ " " ++ showWhere wc

data Bind =
      BindStar
    | BindType Type Id
    | BindId Id
    | BindStarExec
    | BindStarCall
    | BindTypeExec Type Id
    | BindTypeCall Type Id
    | BindIdExec Id
    | BindIdCall Id
  deriving (Eq,Read)

getIdBind :: Bind -> Id
getIdBind (BindId id)         = id
getIdBind (BindIdExec id)     = id
getIdBind (BindIdCall id)     = id
getIdBind (BindType _ id)     = id
getIdBind (BindTypeExec _ id) = id
getIdBind (BindTypeCall _ id) = id
getIdBind _                   = ""

instance Show Bind where
 show BindStar            = "*"
 show (BindType t id)     = t ++ " " ++ id
 show (BindId id)         = id
 show BindStarExec        = "execution *"
 show BindStarCall        = "call *"
 show (BindTypeExec t id) = "execution " ++ t ++ " " ++ id
 show (BindTypeCall t id) = "call " ++ t ++ " " ++ id
 show (BindIdExec id)     = "execution " ++ id
 show (BindIdCall id)     = "call " ++ id

getBindTypeType :: Bind -> Type
getBindTypeType (BindType t id) = t

data Binding =
   BindingVar Bind
  deriving (Eq,Read)

instance Show Binding where
 show (BindingVar b) = show b 

getBind :: Binding -> Bind
getBind (BindingVar bn) = bn

updateMethodCallName :: TriggerDef -> MethodName -> TriggerDef
updateMethodCallName (TriggerDef e arg cpes wc) mn = TriggerDef e arg (updateCpeMethodName cpes mn) wc

updateCpeMethodName :: CompoundTrigger -> MethodName -> CompoundTrigger
updateCpeMethodName (NormalEvent bind id bs) id' = NormalEvent bind id' bs
updateCpeMethodName cpe _                        = cpe

updateCpeMethodCallBody :: CompoundTrigger -> [Bind] -> CompoundTrigger
updateCpeMethodCallBody (NormalEvent bind id bs) bs' = NormalEvent bind id bs'
updateCpeMethodCallBody cpe _                        = cpe

updateMethodCallBody :: TriggerDef -> [Bind] -> TriggerDef
updateMethodCallBody (TriggerDef e arg cpes wc) bs = TriggerDef e arg (updateCpeMethodCallBody cpes bs) wc

type Triggers = [TriggerDef]

-----------------------
-- XML related types --
-----------------------

--Types associated to the KeY API --

type ContractId   = String
type ContractText = String
type Target       = String

data Proof = Proof
  { contractId    :: ContractId
  , contractText  :: ContractText
  , typee         :: Type
  , target        :: Target
  , executionPath :: [EPath]
  } deriving (Show, Eq)
 
data EPath = EPath
  { pathCondition          :: String
  , verified               :: String
  , newPrecondition        :: String
  , terminationKind        :: String 
  , notFulfilledPres       :: [MethodContractApplication]
  , notFulfilledNullChecks :: [MethodContractApplication]
  , notInitValidLoopInvs   :: [MethodContractApplication]
  , notPreservedLoopInvs   :: [MethodContractApplication]
  } deriving (Show, Eq)

data MethodContractApplication = MCA 
 { fileMCA     :: String
 , startLine   :: String
 , startColumn :: String
 , endLine     :: String
 , endColumn   :: String
 , methodMCA   :: String
 , contractMCA :: String
 } deriving(Eq,Show)

-----------
-- Flags --
-----------

type Flags = [Flag]

data Flag = 
   Version 
 | OnlyParse
 | Help
    deriving (Show,Eq)

options :: [OptDescr Flag]
options =
    [ Option "v" ["version"] (NoArg Version) "Show version number"
    , Option "p" ["only_parse"] (NoArg OnlyParse) "Only parse the modelS file"    
    , Option "h" ["help"] (NoArg Help) "Describes the different options"
    ]

------------------------
-- Info in Java Files --
------------------------

data JavaFilesInfo = JavaFilesInfo
 { varsInFiles    :: [(Modifier, Type, Id)]
 , methodsInFiles :: [(Type,Id,[String],MethodInvocations,Modifier)] 
                   --[(returned_type,method_name,arguments,methodsInvokedIn_method_name_body,modifier)]
 } deriving(Eq,Show)

type Modifier = String

------------
-- Lenses --
------------

-- ^. is view, e.g. ppd ^. importsGet
-- %~ is over, e.g. importsGet %~ foo $ ppd
-- .~ is set, e.g. importsGet .~ imps $ ppd

makeLenses ''CModel
makeLenses ''Model
makeLenses ''Context
makeLenses ''Foreach
makeLenses ''Template
makeLenses ''State
makeLenses ''TriggerDef
makeLenses ''CreateActInfo
