open System

open Reader
open Printer

let read (s: string): MalType =
    readStr s

let eval (s: MalType): MalType =
    s

let print (m: MalType): string =
    prStr m

let rep (s: string): string =
    s
    |> read
    |> eval
    |> print

[<EntryPoint>]
let rec main args =
    Console.Write("user> ")
    let line = Console.ReadLine()
    if line = null then
        0
    else
        line
        |> rep
        |> printfn "%s"
        main args
