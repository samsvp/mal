open System

let read (s: string): string =
    s

let eval (s: string): string =
    s

let print (s: string): string =
    s

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
