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
use types::{MalError, MalFn, MalHashable, MalResult, MalType};

use crate::printer::pr_str;

static KEYWORDS: [&str; 5] = ["def!", "let*", "do", "if", "eval"];

fn read(val: &str) -> MalResult {
    reader::read_str(val)
}

fn eval(og_val: &MalType, og_env: &mut Env, og_copy_env: bool) -> MalType {
    match og_env.get("DEBUG-EVAL".to_string()) {
        Some(MalType::Nil) | Some(MalType::Bool(false)) | None => (),
        _ => {
            let s = pr_str(og_val.clone(), true);
            println!("EVAL: {s}")
        }
    }

    let mut val = og_val.clone();
    let mut env = og_env;
    let mut copy_env = og_copy_env;

    let mut live_env;

    loop {
        match val {
            MalType::Symbol(s) if !KEYWORDS.contains(&s.as_str()) => {
                let Some(v) = env.get(s.clone()) else {
                    return MalType::Error(format!("{s} not found"));
                };
                return eval(&v, env, copy_env);
            },
            MalType::List(ref xs) => {
                if xs.len() == 0 {
                    return MalType::List(vec![]);
                }

                let op = eval(&xs[0], env, copy_env);
                match op {
                    MalType::Function(fun) => {
                        if xs.len() > 1 {
                            let values: Vec<MalType> = xs[1..].iter().map(|x| eval(x, env, copy_env)).collect();
                            return fun(values);
                        } else {
                            return fun(vec![]);
                        }
                    },
                    MalType::Symbol(s) if s == "eval" => {
                        let args = xs;
                        if args.len() != 2 {
                            return types::invalid_parameter_length_error(args.len() - 1, 1);
                        }

                        val = eval(&args[1], &mut env.outer(), copy_env);
                    },
                    MalType::Symbol(s) if s == "if" => {
                        let args = xs;
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
                                val = if_false.clone();
                            },
                            _ => {
                                val = if_true.clone();
                            }
                        }
                    },
                    MalType::Symbol(s) if s == "do" => {
                        let args = xs;
                        if args.len() == 1 {
                            return types::invalid_parameter_length_error(args.len(), 2);
                        }

                        let _ = args[1..args.len()-1].iter().map(|x| eval(x, env, false)).collect::<Vec<MalType>>();
                        val = args.last().unwrap().clone();
                    },
                    MalType::Symbol(s) if s == "let*" => {
                        let args = xs;
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

                        let new_env = s.chunks(2).try_fold(Env::new(Some(&env.clone())), |mut acc, chunk| {
                            let (key, value) = (&chunk[0], &chunk[1]);
                            let MalType::Symbol(key_name) = key else {
                                return Err(MalType::Error("Only symbols can be assigned values.".to_string()));
                            };

                            acc.set(key_name.to_string(), value.clone());
                            Ok(acc)
                        });
                        match new_env {
                            Ok(env_) => {
                                let mut new_env = env_.clone();
                                for (key, value) in env_.data {
                                    let MalType::Fn(fn_) = value else {
                                        continue;
                                    };
                                    let new_fn = MalFn { env: Some(new_env.clone()), ..fn_ };
                                    new_env.set(key, MalType::Fn(new_fn));
                                }
                                live_env = new_env;
                                env = &mut live_env;
                                val = args[2].clone();
                            },
                            Err(e) => {
                                return e;
                            }
                        };
                    }
                    MalType::Symbol(s) if s == "def!" => {
                        let args = xs;
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
                        return v;
                    }
                    MalType::Fn(fn_) => {
                        if xs.len() == 1 {
                            if fn_.args.len() != 0 && (!fn_.is_variadic || fn_.args.len() > 1) {
                                return MalType::Fn(fn_);
                            }
                        }

                        let args = if xs.len() == 1 {
                            vec![]
                        } else {
                            xs[1..].to_vec()
                        };

                        if fn_.is_variadic {
                            let got = args.len();
                            let expected = fn_.args.len() - 1;
                            if expected > got {
                                return MalType::Error(format!("Invalid parameter length: got {got}, expected at least {expected}."))
                            }
                        } else if fn_.args.len() != args.len() {
                            return types::invalid_parameter_length_error(args.len() - 1, fn_.args.len());
                        }

                        let mut fn_env = if let Some(env) = fn_.env.clone() {
                            env
                        } else {
                            Env::new(Some(env))
                        };

                        for i in 0..fn_.args.len() {
                            let mut eval_env = env.clone();
                            // variadic argument
                            let val = if fn_.is_variadic && i == fn_.args.len() - 1 {
                                let var_args = if args.len() == i {
                                    MalType::List(vec![])
                                } else {
                                    MalType::List(args[i..].to_vec())
                                };
                                eval(&var_args, &mut eval_env, true)
                            } else {
                                match &args[i] {
                                    MalType::Fn(_) => args[i].clone(),
                                    v => eval(v, &mut eval_env, true),
                                }
                            };
                            fn_env.set(fn_.args[i].clone(), val);
                        }
                        live_env = fn_env.clone();
                        env = &mut live_env;
                        val = *fn_.body;
                        copy_env = true;
                    },
                    MalType::Error(e) => {
                        return MalType::Error(e);
                    }
                    _ => {
                        let values: Vec<MalType> = xs.into_iter().map(|x| eval(&x, env, copy_env)).collect();
                        return MalType::List(values);
                    },
                }
            }
            MalType::Vector(xs) => {
                let values: Vec<MalType> = xs.into_iter().map(|x| eval(&x, env, copy_env)).collect();
                return MalType::Vector(values);
            }
            MalType::Dict(ds) => {
                let values: HashMap<MalHashable, MalType> =
                ds
                    .iter()
                    .map(|(key, x)| (key.clone(), eval(x, env, copy_env)))
                    .collect();
                return MalType::Dict(values);
            }
            MalType::Fn(fn_) => {
                let fn_ = fn_.clone();
                let fn_ = if copy_env && fn_.env.is_none() {
                    MalFn { env: Some(env.clone()), ..fn_ }
                } else {
                    fn_
                };
                return MalType::Fn(fn_);
            }
            _ => {
                return val.clone();
            }
        }
    }
}

fn print(val: MalType) -> String {
    let s = pr_str(val.clone(), false);
    match val {
        MalType::String(_) => format!("\"{s}\""),
        _ => s
    }
}

fn re(val: &str, env: &mut Env) -> MalResult {
    match read(val) {
        Ok(m) => Ok(eval(&m, env, false)),
        Err(err) => Err(MalError::new(format!("Parse error: {err}"))),
    }
}

fn rep(val: &str, env: &mut Env) -> String {
    match re(val, env) {
        Ok(v) => print(v),
        Err(err) => err.to_string(),
    }
}

fn main() -> Result<()> {
    let mut rl = DefaultEditor::new()?;
    let _ = rl.load_history("history.txt");

    let mut env = get_env();

    re("(def! not (fn* (a) (if a false true)))", &mut env)
        .expect("'not' function failed to register.");
    re(r#"(def! load-file (fn* (f) (eval (read-string (str "(do " (slurp f) " nil)")))))"#, &mut env)
        .expect("'load-file' function failed to register.");

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
