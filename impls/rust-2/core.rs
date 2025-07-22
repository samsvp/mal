use std::collections::HashMap;

use crate::printer::pr_str;
use crate::types::{self, MalType};
use crate::env::Env;

macro_rules! do_op {
    ($args: expr, MalType::$variant:ident, $init:expr, $fold_op:expr) => {{
        let res = $args.iter().try_fold($init, |acc, v| {
            let MalType::$variant(val) = v else {
                return Err(types::invalid_argument_error(v.clone()));
            };

            Ok($fold_op(acc, val))
        });
        match res {
            Ok(i) => MalType::$variant(i),
            Err(e) => e,
        }
    }};
}

macro_rules! cmp {
    ($args: expr, MalType::$variant:ident, $init:expr, $op:tt) => {{
        let mut res = MalType::Bool(true);
        for v in $args[1..].iter() {
            let MalType::$variant(i) = v else {
                res = MalType::Bool(false);
                break;
            };
            if !(*i $op $init) {
                res = MalType::Bool(false);
                break;
            }
        }
        res
    }};
}

macro_rules! do_cmp_fn {
    ($args: expr, $op:tt) => {{
        if $args.len() == 0 || $args.len() == 1 {
            return MalType::Error("Comparision needs at least two parameters.".to_string());
        }

        match &$args[0] {
            MalType::Bool(initial) => {
                let init = initial.clone();
                cmp!($args, MalType::Bool, init, $op)
            }
            MalType::Int(initial) => {
                let init = initial.clone();
                cmp!($args, MalType::Int, init, $op)
            }
            MalType::String(initial) => {
                let init = initial.clone();
                cmp!($args, MalType::String, init, $op)
            }
            m => MalType::Error(format!("Unsupported type for comparision: {m:#?}"))
        }
    }};
}

fn less(args: Vec<MalType>) -> MalType {
    do_cmp_fn!(args, >)
}
fn less_eq(args: Vec<MalType>) -> MalType {
    do_cmp_fn!(args, >=)
}
fn bigger(args: Vec<MalType>) -> MalType {
    do_cmp_fn!(args, <)
}
fn bigger_eq(args: Vec<MalType>) -> MalType {
    do_cmp_fn!(args, <=)
}
fn equals(args: Vec<MalType>) -> MalType {
    if args.len() == 0 || args.len() == 1 {
        return MalType::Error("Comparision needs at least two parameters.".to_string());
    }

    match &args[0] {
        MalType::Vector(vs1) | MalType::List(vs1) => {
            let res = args[1..].iter().all(|arg| match arg {
                MalType::List(vs2) | MalType::Vector(vs2) => {
                    if vs1.len() != vs2.len() {
                        return false;
                    }
                    let mut eq = true;
                    for i in 0..vs1.len() {
                        eq = match equals(vec![vs1[i].clone(), vs2[i].clone()]) {
                            MalType::Bool(b) => b,
                            _ => false,
                        };
                        if ! eq {
                            break;
                        }
                    }
                    eq
                }
                _ => false,
            });
            MalType::Bool(res)
        }
        MalType::Nil => {
            let res = args[1..].iter().all(|a| match a {
                MalType::Nil => true,
                _ => false,
            });
            MalType::Bool(res)
        }
        _ => do_cmp_fn!(args, ==),
    }
}
fn not_equals(args: Vec<MalType>) -> MalType {
    do_cmp_fn!(args, !=)
}

fn list(args: Vec<MalType>) -> MalType {
    MalType::List(args)
}

fn list_question(args: Vec<MalType>) -> MalType {
    let res = args.iter().all(|a| match a {
        MalType::List(_) => true,
        _ => false
    });
    MalType::Bool(res)
}

fn empty_question(args: Vec<MalType>) -> MalType {
    let res = args.iter().all(|a| match a {
        MalType::List(v) | MalType::Vector(v) => v.is_empty(),
        MalType::Dict(d) => d.is_empty(),
        _ => false
    });
    MalType::Bool(res)
}

fn count(args: Vec<MalType>) -> MalType {
    if args.len() == 1 {
        return match &args[0] {
            MalType::List(v) | MalType::Vector(v) => MalType::Int(v.len() as i64),
            MalType::Nil => MalType::Int(0),
            MalType::Dict(d) => MalType::Int(d.len() as i64),
            _ => MalType::Error("Type is not an enumerable".to_string()),
        };
    }

    let res = args.iter().map(|a| match a {
        MalType::List(v) | MalType::Vector(v) => MalType::Int(v.len() as i64),
        MalType::Nil => MalType::Int(0),
        MalType::Dict(d) => MalType::Int(d.len() as i64),
        _ => MalType::Error("Type is not an enumerable".to_string()),
    }).collect();
    MalType::List(res)
}

fn add(args: Vec<MalType>) -> MalType {
    if args.len() == 0 {
        return MalType::Error("Sum on empty list".to_string());
    }

    match &args[0] {
        MalType::Int(_) => {
            do_op!(args, MalType::Int, 0, |acc, v| acc + v)
        }
        MalType::String(_) => {
            do_op!(args, MalType::String, "".to_string(), |acc, v| acc + v)
        }
        MalType::List(_) => {
            do_op!(args, MalType::List, Vec::new(), |acc, v: &Vec<MalType>| [acc, v.clone()].concat())
        }
        MalType::Vector(_) => {
            do_op!(args, MalType::Vector, Vec::new(), |acc, v: &Vec<MalType>| [acc, v.clone()].concat())
        }
        t => MalType::Error(format!("Unsupported type for '+': {t:#?}"))
    }
}

fn sub(args: Vec<MalType>) -> MalType {
    if args.len() == 0 {
        return MalType::Error("Subtraction on empty list".to_string());
    }

    match args[0] {
        MalType::Int(v) => {
            if args.len() == 1 {
                MalType::Int(v)
            } else {
                do_op!(args[1..], MalType::Int, v, |acc, v| acc - v)
            }
        }
        _ => MalType::Error("Unsupported type for '-'".to_string())
    }
}

fn mult(args: Vec<MalType>) -> MalType {
    if args.len() == 0 {
        return MalType::Error("Multiplication on empty list".to_string());
    }

    match &args[0] {
        MalType::Int(_) => {
            do_op!(args, MalType::Int, 1, |acc, v| acc * v)
        }
        v => {
            MalType::Error(format!("Unsupported type for '*': {v:#?}"))
        }
    }
}

fn div(args: Vec<MalType>) -> MalType {
    if args.len() == 0 {
        return MalType::Error("Division on empty list".to_string());
    }

    match args[0] {
        MalType::Int(v) => {
            if args.len() == 1 {
                return MalType::Int(v);
            }
            let res = args[1..].iter().try_fold(v, |acc, v| {
                let MalType::Int(val) = v else {
                    return Err(types::invalid_argument_error(v.clone()));
                };
                if *val == 0 {
                    return Err(types::division_by_zero_error());
                }

                Ok(acc / val)
            });
            match res {
                Ok(i) => MalType::Int(i),
                Err(e) => e,
            }
        }
        _ => MalType::Error("Unsupported type for '/'".to_string())
    }
}

fn pr_str_(args: Vec<MalType>) -> MalType {
    let v = args.iter().map(|a| pr_str(a.clone(), true)).collect::<Vec<String>>().join(" ");
    MalType::String(v)
}

fn str_(args: Vec<MalType>) -> MalType {
    let v = args.iter().map(|a| pr_str(a.clone(), false)).collect::<Vec<String>>().join("");
    MalType::String(v)
}

fn prn(args: Vec<MalType>) -> MalType {
    let strs: Vec<String> = args.iter().map(|x| pr_str(x.clone(), true)).collect();
    let v = format!("{}", strs.join(" "));
    println!("{v}");
    MalType::Nil
}

fn println_(args: Vec<MalType>) -> MalType {
    let s = args
        .iter()
        .map(|a| {
            pr_str(a.clone(), false)
                .replace("\\n", "\n")
                .replace("\\\"", "\"")
        })
        .collect::<Vec<String>>()
        .join(" ");
    println!("{s}");
    MalType::Nil
}

pub fn get_env() -> Env {
    let env: HashMap<String, MalType> = HashMap::from([
        ("+".to_string(), MalType::Function(add)),
        ("-".to_string(), MalType::Function(sub)),
        ("*".to_string(), MalType::Function(mult)),
        ("/".to_string(), MalType::Function(div)),
        ("<".to_string(), MalType::Function(less)),
        ("<=".to_string(), MalType::Function(less_eq)),
        (">".to_string(), MalType::Function(bigger)),
        (">=".to_string(), MalType::Function(bigger_eq)),
        ("=".to_string(), MalType::Function(equals)),
        ("!=".to_string(), MalType::Function(not_equals)),
        ("list".to_string(), MalType::Function(list)),
        ("list?".to_string(), MalType::Function(list_question)),
        ("empty?".to_string(), MalType::Function(empty_question)),
        ("count".to_string(), MalType::Function(count)),
        ("prn".to_string(), MalType::Function(prn)),
        ("pr-str".to_string(), MalType::Function(pr_str_)),
        ("str".to_string(), MalType::Function(str_)),
        ("println".to_string(), MalType::Function(println_)),
    ]);
    Env::from(env)
}
