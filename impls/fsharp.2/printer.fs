module Printer

open Reader

let rec prCollection arr cType =
    let openChar, closeChar =
        match cType with
        | C_VECTOR ->  "[", "]"
        | C_LIST -> "(", ")"
        | C_HASH_MAP -> "{", "}"
    let s =
        arr
        |> Array.fold (fun acc m ->
            if acc <> openChar then
                sprintf "%s %s" acc (prStr m)
            else
                sprintf "%s%s" acc (prStr m)

        ) openChar
    s + closeChar

and prStr (m: MalType): string =
    match m with
    | MalNumber n ->
        string n
    | MalString s ->
        sprintf "\"%s\"" s
    | MalSymbol s ->
        s
    | MalBool b ->
        let s = string b
        s.ToLower()
    | MalNil ->
        "nil"
    | MalError e ->
        e
    | MalList arr ->
        prCollection arr C_LIST
    | MalVector arr ->
        prCollection arr C_VECTOR
    | MalHashMap arr ->
        prCollection arr C_HASH_MAP
