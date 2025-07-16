module Printer

open Types
open Reader

let rec prCollection arr cType =
    let openChar, closeChar =
        match cType with
        | C_VECTOR ->  "[", "]"
        | C_LIST -> "(", ")"
        | _ -> failwith "Unsupported collection"
    let s =
        arr
        |> Seq.fold (fun acc m ->
            if acc <> openChar then
                sprintf "%s %s" acc (prStr m)
            else
                sprintf "%s%s" acc (prStr m)

        ) openChar
    s + closeChar

and prHashMap m =
    let openChar = "{"
    let closeChar = "}"
    let s =
        m
        |> Map.fold (fun acc key v ->
            if acc <> openChar then
                sprintf "%s %s %s" acc (prStr key) (prStr v)
            else
                sprintf "%s%s %s" acc (prStr key) (prStr v)
        ) openChar
    s + closeChar


and prStr (m: MalType): string =
    match m with
    | MalNumber n ->
        string n
    | MalString s ->
        sprintf "\"%s\"" s
    | MalSymbol s
    | MalKeyword s ->
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
    | MalHashMap m ->
        prHashMap m
