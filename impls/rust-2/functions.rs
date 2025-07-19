use std::collections::HashMap;

use crate::types::{self, MalType};
use crate::env::Env;

macro_rules! do_op {
    ($args: expr, MalType::$variant:ident, $init:expr, $fold_op:expr) => {{
        let res = $args.iter().try_fold($init, |acc, v| {
            let MalType::$variant(val) = v else {
                return Err(types::invalid_argument_error());
            };

            Ok($fold_op(acc, val))
        });
        match res {
            Ok(i) => MalType::$variant(i),
            Err(e) => e,
        }
    }};
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

    match args[0] {
        MalType::Int(_) => {
            do_op!(args, MalType::Int, 1, |acc, v| acc * v)
        }
        _ => MalType::Error("Unsupported type for '*'".to_string())
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
                    return Err(types::invalid_argument_error());
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

pub fn get_env() -> Env {
    let env: HashMap<String, MalType> = HashMap::from([
        ("+".to_string(), MalType::Function(add)),
        ("-".to_string(), MalType::Function(sub)),
        ("*".to_string(), MalType::Function(mult)),
        ("/".to_string(), MalType::Function(div)),
    ]);
    Env::from(env)
}
