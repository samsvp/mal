module Reader

open System.Text.RegularExpressions
open Types

type Token =
    | EOF
    | PAREN_OPEN
    | PAREN_CLOSE
    | CURLY_BRACKET_OPEN
    | CURLY_BRACKET_CLOSE
    | SQUARE_BRACKET_OPEN
    | SQUARE_BRACKET_CLOSE
    | SINGLEQUOTE
    | BACKTICK
    | TILDE
    | TILDE_AT
    | SPLICEUNQUOTE
    | HAT
    | AT
    | NONE
    | NIL
    | BOOL of bool
    | COMMENT of string
    | ERROR of string
    | STRING of string
    | SYMBOL of string
    | KEYWORD of string
    | NUMBER of float

type Reader =
    { Tokens: Token array
      Position: int
    }

let tokenize s =
    match s with
    | "@" -> AT
    | "(" -> PAREN_OPEN
    | ")" -> PAREN_CLOSE
    | "{" -> CURLY_BRACKET_OPEN
    | "}" -> CURLY_BRACKET_CLOSE
    | "[" -> SQUARE_BRACKET_OPEN
    | "]" -> SQUARE_BRACKET_CLOSE
    | "~" -> TILDE
    | "'" -> SINGLEQUOTE
    | "`" -> BACKTICK
    | "^" -> HAT
    | "~@" -> TILDE_AT
    | "true" -> BOOL true
    | "false" -> BOOL false
    | "nil" -> NIL
    | _ ->
        if s.Length = 0 then
            NONE

        else
        match s.[0] with
        | '"' ->
            if s.Length > 1 && s.[s.Length-1] = '"' then
                let mutable i = s.Length - 2
                let mutable backslashAmount = 0
                while i <> 0 && s.[i] = '\\' do
                    backslashAmount <- backslashAmount + 1
                    i <- i - 1
                if backslashAmount % 2 = 0 then
                    s.[1..s.Length-2] |> STRING
                else
                    ERROR "EOF Unclosed string"
            else
                ERROR "EOF Unclosed string"
        | ';' ->
            s.[1..s.Length-1] |> COMMENT
        | ':' ->
            KEYWORD s
        | _ ->
            let success, f = System.Double.TryParse s
            if success then
                NUMBER f
            else
                SYMBOL s

let peek r =
    if r.Position < r.Tokens.Length then
        Some r.Tokens.[r.Position]
    else
        None

let inline next r =
    { r with Position = r.Position + 1 }

let readAtom r: MalType =
    match peek r with
    | Some NIL -> MalNil
    | Some (BOOL b) -> MalBool b
    | Some (STRING s) -> MalString s
    | Some (SYMBOL s) -> MalSymbol s
    | Some (KEYWORD s) -> MalKeyword s
    | Some (NUMBER n) -> MalNumber n
    | Some (ERROR e) ->
        MalError "EOF"
    | Some t ->
        sprintf "Unknown atom %A" t
        |> MalError
    | None ->
        MalError "EOF"

let rec readCollection r acc cType =
    match cType, peek r with
    | C_HASH_MAP, Some CURLY_BRACKET_CLOSE
    | C_VECTOR, Some SQUARE_BRACKET_CLOSE
    | C_LIST, Some PAREN_CLOSE ->
        let value =
            acc
            |> List.rev
            |> fun value ->
                match cType with
                | C_VECTOR ->
                    value
                    |> List.toArray
                    |> MalVector
                | C_LIST ->
                    MalList value
                | C_HASH_MAP ->
                    if value.Length % 2 <> 0 then
                        MalError "EOF hash map must have an even number of elements"
                    else

                    value
                    |> List.chunkBySize 2
                    |> List.map (fun vs -> vs.[0], vs.[1])
                    |> Map.ofList
                    |> MalHashMap
        next r, value
    | _, Some _ ->
        let r, value = readForm r
        readCollection r (value :: acc) cType
    | _, None ->
        r, MalError "EOF unclosed bracket"

and readVec r acc =
    readCollection r acc C_VECTOR
and readList r acc =
    readCollection r acc C_LIST
and readHashMap r acc =
    readCollection r acc C_HASH_MAP
and readForm r =
    match peek r with
    | Some PAREN_OPEN ->
        readList (next r) []
    | Some SQUARE_BRACKET_OPEN ->
        readVec (next r) []
    | Some CURLY_BRACKET_OPEN ->
        readHashMap (next r) []
    | Some _ ->
        let atom = readAtom r
        next r, atom
    | None ->
        r, MalError "EOF"

let readStr (str: string): MalType =
    let tokens =
        Regex.Matches(
            str,
            """[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)"""
        )
        |> Seq.toArray
        |> Array.map (fun m ->
            if m.Groups.Count > 1 && m.Groups.[1].Success then
                m.Groups.[1].Value
            else
                ""
            |> tokenize
        )

    { Tokens = tokens
      Position = 0
    }
    |> readForm
    |> snd

