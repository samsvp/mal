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
        return types::invalid_argument_error();
    };
    let v = eval(args[2].clone(), env);
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
        return types::invalid_argument_error();
    };
    if s.len() % 2 != 0 {
        return types::invalid_parameter_length_error(s.len(), s.len() + 1);
    }

    let new_env = s.chunks(2).try_fold(Env::new(Some(env)), |mut acc, chunk| {
        let (key, value) = (&chunk[0], &chunk[1]);
        let MalType::Symbol(key_name) = key else {
            return Err(MalType::Error("Only symbols can be assigned values.".to_string()));
        };
        let mut eval_env = Env::new(Some(&acc));
        match eval(value.clone(), &mut eval_env) {
            MalType::Error(e) => Err(MalType::Error(e)),
            val => {
                acc.set(key_name.to_string(), val);
                Ok(acc)
            }
        }
    });
    match new_env {
        Ok(mut env) => eval(args[2].clone(), &mut env),
        Err(e) => e,
    }
}

fn do_(args: &Vec<MalType>, env: &mut Env) -> MalType {
    if args.len() == 1 {
        return types::invalid_parameter_length_error(args.len(), 2);
    }

    args[1..].iter().map(|x| eval(x.clone(), env)).collect::<Vec<MalType>>().last().cloned().unwrap()
}

fn if_(args: &Vec<MalType>, env: &mut Env) -> MalType {
    if args.len() != 3 && args.len() != 4 {
        if args.len() < 3 {
            return types::invalid_parameter_length_error(args.len(), 3);
        } else {
            return types::invalid_parameter_length_error(args.len(), 4);
        }
    }

    match eval(args[1].clone(), env) {
        MalType::Nil | MalType::Bool(false) => {
            if args.len() == 3 {
                return MalType::Nil;
            }
            eval(args[3].clone(), env)
        },
        _ => eval(args[2].clone(), env)
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
        let mut arg_env = Env::new(Some(&fn_env.clone()));
        let value = eval(args[i].clone(), &mut arg_env);
        fn_env.set(fn_.args[i].clone(), value);
    }
    eval(*fn_.body, &mut fn_env)
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

fn eval(val: MalType, env: &mut Env) -> MalType {
    match val {
        MalType::Symbol(s) if !KEYWORDS.contains_key(&s) => {
            let Some(v) = env.get(s.clone()) else {
                return MalType::Error(format!("{s} not found"));
            };
            v.clone()
        },
        MalType::List(xs) => {
            if xs.len() == 0 {
                return MalType::List(vec![]);
            }

            let op = eval(xs[0].clone(), env);
            match op {
                MalType::Function(fun) => {
                    if xs.len() > 1 {
                        let values: Vec<MalType> = xs[1..].iter().map(|x| eval(x.clone(), env)).collect();
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
                    let values: Vec<MalType> = xs.into_iter().map(|x| eval(x, env)).collect();
                    MalType::List(values)
                },
            }
        }
        MalType::Vector(xs) => {
            let values: Vec<MalType> = xs.into_iter().map(|x| eval(x, env)).collect();
            MalType::Vector(values)
        }
        MalType::Dict(ds) => {
            let values: HashMap<MalHashable, MalType> = ds.into_iter().map(|(key, x)| (key, eval(x, env))).collect();
            MalType::Dict(values)
        }
        MalType::Fn(fn_) => {
            let fn_ = if fn_.env.is_none() {
                MalFn { env: Some(env.clone()), ..fn_ }
            } else {
                fn_
            };
            MalType::Fn(fn_)
        }
        _ => val
    }
}

fn print(val: MalType) -> MalType {
    val
}

fn rep(val: &str, env: &mut Env) -> MalType {
    print(
        eval(
            read(val),
            env
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
                let v = pr_str(v);
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
