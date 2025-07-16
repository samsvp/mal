module Types

type MalSymbol = string

type CollectionTypes =
    | C_LIST
    | C_VECTOR
    | C_HASH_MAP

type MalType =
    | MalNumber of float
    | MalString of MalSymbol
    | MalSymbol of string
    | MalKeyword of string
    | MalBool of bool
    | MalNil
    | MalList of MalType list
    | MalVector of MalType array
    | MalHashMap of Map<MalType, MalType>
    | MalError of string

type MalFunction = MalType list -> MalType

type MalForm =
    | MalType of MalType
    | MalFunction of MalFunction
