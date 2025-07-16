open System

open Reader
open Printer
open Functions
open System.Collections.Generic

let env =
    dict [
        "+", add
        "-", subtract
        "/", divide
        "*", multiply
    ] |> Dictionary<string, MalFunction>

let read (s: string): MalType =
    readStr s

let eval (env: Dictionary<string, MalFunction>) (ast: MalType): MalType =
    let rec eval env acc fn ast =
        match ast with
        | MalSymbol s ->
            let success, fn = Dictionary.TryGetValue s
            if not success then
                sprintf "Could not find symbol %s" s
                |> MalError
            else
                s
        | MalList xs -> xs


let print (m: MalType): string =
    prStr m

let rep (env: Dictionary<string, MalFunction>) (s: string): string =
    s
    |> read
    |> eval env
    |> print

[<EntryPoint>]
let rec main args =
    Console.Write("user> ")
    let line = Console.ReadLine()
    if line = null then
        0
    else
        line
        |> rep env
        |> printfn "%s"
        main args
