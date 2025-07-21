mod reader;
mod printer;
mod types;
mod core;
mod env;

use std::collections::HashMap;

use env::Env;
use core::get_env;
use rustyline::error::ReadlineError;
use rustyline::{DefaultEditor, Result};
use types::{MalHashable, MalType, MalFn};

use crate::printer::pr_str;

fn def_bang(args: &Vec<MalType>, env: &mut Env) -> MalType {
    if args.len() != 3 {
        return types::invalid_parameter_length_error(args.len(), 3);
    }
    let MalType::Symbol(ref s) = args[1] else {
        return types::invalid_argument_error(args[1].clone());
    };
    let v = eval(&args[2], env, false);
    match v {
        MalType::Error(_) => (),
        _ => env.set(s.to_string(), v.clone()),
    }
    v
}

fn let_star(args: &Vec<MalType>, env: &mut Env) -> MalType {
    if args.len() != 3 {
        return types::invalid_parameter_length_error(args.len(), 3);
    }
    let maybe_s = match &args[1] {
        MalType::List(arr) => Some(arr),
        MalType::Vector(arr) => Some(arr),
        _ => None,
    };
    let Some(ref s) = maybe_s else {
        return types::invalid_argument_error(args[1].clone());
    };
    if s.len() % 2 != 0 {
        return types::invalid_parameter_length_error(s.len(), s.len() + 1);
    }

    let new_env = s.chunks(2).try_fold(Env::new(Some(env)), |mut acc, chunk| {
        let (key, value) = (&chunk[0], &chunk[1]);
        let MalType::Symbol(key_name) = key else {
            return Err(MalType::Error("Only symbols can be assigned values.".to_string()));
        };

        acc.set(key_name.to_string(), value.clone());
        Ok(acc)
    });
    match new_env {
        Ok(env) => {
            let mut new_env = env.clone();
            for (key, value) in env.data {
                let MalType::Fn(fn_) = value else {
                    continue;
                };
                let new_fn = MalFn { env: Some(new_env.clone()), ..fn_ };
                new_env.set(key, MalType::Fn(new_fn));
            }
            eval(&args[2], &mut new_env, true)
        },
        Err(e) => e,
    }
}

fn do_(args: &Vec<MalType>, env: &mut Env) -> MalType {
    if args.len() == 1 {
        return types::invalid_parameter_length_error(args.len(), 2);
    }

    args[1..].iter().map(|x| eval(x, env, false)).collect::<Vec<MalType>>().last().cloned().unwrap()
}

fn if_(args: &Vec<MalType>, env: &mut Env) -> MalType {
    if args.len() != 3 && args.len() != 4 {
        if args.len() < 3 {
            return types::invalid_parameter_length_error(args.len(), 3);
        } else {
            return types::invalid_parameter_length_error(args.len(), 4);
        }
    }
    let condition = &args[1];
    let if_true = &args[2];

    match eval(&condition, env, false) {
        MalType::Nil | MalType::Bool(false) => {
            if args.len() == 3 {
                return MalType::Nil;
            }
            let if_false = &args[3];
            eval(&if_false, env, false)
        },
        _ => eval(&if_true, env, false)
    }
}

fn fn_star(fn_: MalFn, args: Vec<MalType>, env: &Env) -> MalType {
    if fn_.args.len() != args.len() {
        return types::invalid_parameter_length_error(args.len() - 1, fn_.args.len());
    }

    let mut fn_env = if let Some(env) = fn_.env.clone() {
        env
    } else {
        Env::new(Some(env))
    };

    for i in 0..args.len() {
        let mut eval_env = env.clone();
        let val = match &args[i] {
            MalType::Fn(_) => args[i].clone(),
            v => eval(v, &mut eval_env, true),
        };
        fn_env.set(fn_.args[i].clone(), val);
    }
    eval(&fn_.body, &mut fn_env, true)
}

static KEYWORDS: phf::Map<&'static str, fn(&Vec<MalType>, &mut Env) -> MalType> = phf::phf_map!{
    "def!" => def_bang,
    "let*" => let_star,
    "do" => do_,
    "if" => if_,
};

fn read(val: &str) -> MalType {
    reader::read_str(val)
}

fn eval(val: &MalType, env: &mut Env, copy_env: bool) -> MalType {
    match env.get("DEBUG-EVAL".to_string()) {
        Some(MalType::Nil) | Some(MalType::Bool(false)) | None => (),
        _ => {
            let s = pr_str(val.clone(), true);
            println!("EVAL: {s}")
        }
    }

    match val {
        MalType::Symbol(s) if !KEYWORDS.contains_key(&s) => {
            let Some(v) = env.get(s.clone()) else {
                return MalType::Error(format!("{s} not found"));
            };
            eval(&v, env, copy_env)
        },
        MalType::List(xs) => {
            if xs.len() == 0 {
                return MalType::List(vec![]);
            }

            let op = eval(&xs[0], env, copy_env);
            match op {
                MalType::Function(fun) => {
                    if xs.len() > 1 {
                        let values: Vec<MalType> = xs[1..].iter().map(|x| eval(x, env, copy_env)).collect();
                        fun(values)
                    } else {
                        fun(vec![])
                    }
                },
                MalType::Symbol(s) if KEYWORDS.contains_key(&s) => {
                    KEYWORDS.get(&s).unwrap()(&xs, env)
                },
                MalType::Fn(fn_) => {
                    if xs.len() == 1 {
                        if fn_.args.len() != 0 {
                            return MalType::Fn(fn_);
                        } else {
                            return fn_star(fn_, vec![], env);
                        }
                    }

                    fn_star(fn_, xs[1..].to_vec(), env)
                },
                MalType::Error(e) => MalType::Error(e),
                _ => {
                    let values: Vec<MalType> = xs.into_iter().map(|x| eval(x, env, copy_env)).collect();
                    MalType::List(values)
                },
            }
        }
        MalType::Vector(xs) => {
            let values: Vec<MalType> = xs.into_iter().map(|x| eval(x, env, copy_env)).collect();
            MalType::Vector(values)
        }
        MalType::Dict(ds) => {
            let values: HashMap<MalHashable, MalType> =
                ds
                .iter()
                .map(|(key, x)| (key.clone(), eval(x, env, copy_env)))
                .collect();
            MalType::Dict(values)
        }
        MalType::Fn(fn_) => {
            let fn_ = fn_.clone();
            let fn_ = if copy_env && fn_.env.is_none() {
                MalFn { env: Some(env.clone()), ..fn_ }
            } else {
                fn_
            };
            MalType::Fn(fn_)
        }
        _ => val.clone(),
    }
}

fn print(val: MalType) -> String {
    pr_str(val, true)
}

fn rep(val: &str, env: &mut Env) -> String {
    print(
        eval(
            &read(val),
            env,
            false,
        )
    )
}

fn main() -> Result<()> {
    let mut rl = DefaultEditor::new()?;
    let _ = rl.load_history("history.txt");

    let mut env = get_env();

    loop {
        let readline = rl.readline("user> ");
        match readline {
            Ok(line) => {
                let v = rep(&line, &mut env);
                let _ = rl.add_history_entry(&line);
                println!("{v}");
            },
            Err(ReadlineError::Interrupted) | Err(ReadlineError::Eof) => break,
            Err(err) => {
                println!("Error: {err}");
                break;
            }
        }
    }

    let _ = rl.save_history("history.txt");
    Ok(())
}
