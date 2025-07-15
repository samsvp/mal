module Reader

open System.Text.RegularExpressions

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
    | TOKEN of string
    | KEYWORD of string
    | NUMBER of float

type Reader =
    { Tokens: Token array
      Position: int
    }

let wordToToken s =
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
                s.[1..s.Length-2] |> STRING
            else
                ERROR "Unclosed string"
        | ';' ->
            s.[1..s.Length-1] |> COMMENT
        | _ ->
            let success, f = System.Double.TryParse s
            if success then
                NUMBER f
            else
                TOKEN s


let tokenize (str: string): Reader =
    let tokens =
        Regex.Matches(
            str,
            """[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)"""
        )
        |> Seq.toArray
        |> Array.map (fun s ->
            s.Value.Trim()
            |> wordToToken
        )

    { Tokens = tokens
      Position = 0
    }

let peak r =
    r.Tokens.[r.Position]

let next r =
    let r =
        { r with Position = r.Position + 1 }
    r, peak r

