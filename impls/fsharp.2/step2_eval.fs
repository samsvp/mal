open System

open Types
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
    ] |> Dictionary<MalSymbol, MalFunction>

let read (s: string): MalType =
    readStr s

let rec eval (env: Dictionary<string, MalFunction>) (ast: MalType): MalType =
    match ast with
    | MalSymbol s ->
        let success = env.ContainsKey s
        if not success then
            sprintf "Could not find symbol %s" s
            |> MalError
        else
            ast
    | MalList (x :: xs) ->
        let value = eval env x
        match value with
        | MalError _ ->
            value
        | MalSymbol s ->
            let fn = env.[s]
            xs
            |> List.map (eval env)
            |> fn
        | _ ->
            sprintf "Error: %A used as function name" value
            |> MalError
    | MalVector vs ->
        vs
        |> Array.map (eval env)
        |> MalVector
    | MalHashMap hs ->
        hs
        |> Map.map (fun _ v -> eval env v)
        |> MalHashMap
    | _ ->
        ast


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
