module Functions

open Reader

let add (xs: MalType list): MalType =
    match xs with
    | [ MalNumber a ] -> a |> MalNumber
    | [ MalString a ] -> a |> MalString
    | [ MalList a ] -> a |> MalList
    | [ MalVector a ] -> a |> MalVector
    | MalNumber a :: rest ->
        rest
        |> List.fold(fun acc n ->
            match acc, n with
            | MalNumber acc, MalNumber n ->
                acc + n |> MalNumber
            | MalError _, _ ->
                acc
            | _ ->
                sprintf "Can not add %f with %A" a rest
                |> MalError
        ) (MalNumber a)
    | MalString a :: rest ->
        rest
        |> List.fold(fun acc n ->
            match acc, n with
            | MalString acc, MalString n ->
                acc + n |> MalString
            | MalError _, _ ->
                acc
            | _ ->
                sprintf "Can not add %s with %A" a rest
                |> MalError
        ) (MalString a)
    | MalList a :: rest ->
        rest
        |> List.fold(fun acc n ->
            match acc, n with
            | MalList acc, MalList n ->
                Array.concat [acc; n] |> MalList
            | MalError _, _ ->
                acc
            | _ ->
                sprintf "Can not add %A with %A" a rest
                |> MalError
        ) (MalList a)
    | MalVector a :: rest ->
        rest
        |> List.fold(fun acc n ->
            match acc, n with
            | MalVector acc, MalVector n ->
                Array.concat [acc; n] |> MalVector
            | MalError _, _ ->
                acc
            | _ ->
                sprintf "Can not add %A with %A" a rest
                |> MalError
        ) (MalVector a)
    | v ->
        sprintf "Unsupported values for addition %A" v
        |> MalError

let subtract (xs: MalType list): MalType =
    match xs with
    | [ MalNumber a ] -> (-a) |> MalNumber
    | MalNumber a :: rest ->
        rest
        |> List.fold(fun acc n ->
            match acc, n with
            | MalNumber acc, MalNumber n ->
                acc - n |> MalNumber
            | MalError _, _ ->
                acc
            | _ ->
                sprintf "Can not divide %f with %A" a rest
                |> MalError
        ) (MalNumber a)
    | v ->
        sprintf "Unsupported values for subtraction %A" v
        |> MalError

let multiply (xs: MalType list): MalType =
    match xs with
    | [ MalNumber a ] -> a |> MalNumber
    | MalNumber a :: rest ->
        rest
        |> List.fold(fun acc n ->
            match acc, n with
            | MalNumber acc, MalNumber n ->
                acc * n |> MalNumber
            | MalError _, _ ->
                acc
            | _ ->
                sprintf "Can not multiply %f with %A" a rest
                |> MalError
        ) (MalNumber a)
    | v ->
        sprintf "Unsupported values for multiplication %A" v
        |> MalError

let divide (xs: MalType list): MalType =
    match xs with
    | [ MalNumber a ] -> a |> MalNumber
    | MalNumber a :: rest ->
        rest
        |> List.fold(fun acc n ->
            match acc, n with
            | MalNumber acc, MalNumber n when n <> 0.0 ->
                acc / n |> MalNumber
            | MalNumber acc, MalNumber n when n = 0.0 ->
                MalError "Division by 0"
            | MalError _, _ ->
                acc
            | _ ->
                sprintf "Can not divide %f with %A" a rest
                |> MalError
        ) (MalNumber a)
    | v ->
        sprintf "Unsupported values for division %A" v
        |> MalError
