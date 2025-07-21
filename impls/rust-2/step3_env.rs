mod reader;
mod printer;
mod types;
mod functions;
mod env;

use std::collections::HashMap;

use env::Env;
use functions::get_env;
use rustyline::error::ReadlineError;
use rustyline::{DefaultEditor, Result};
use types::{MalHashable, MalType};

use crate::printer::pr_str;

fn read(val: &str) -> MalType {
    reader::read_str(val)
}

fn def_bang(args: &Vec<MalType>, env: &mut Env) -> MalType {
    if args.len() != 3 {
        return types::invalid_parameter_length_error(args.len(), 3);
    }
    let MalType::Symbol(ref s) = args[1] else {
        return types::invalid_argument_error(args[1].clone());
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

static KEYWORDS: phf::Map<&'static str, fn(&Vec<MalType>, &mut Env) -> MalType> = phf::phf_map!{
    "def!" => def_bang,
    "let*" => let_star,
};

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
                    let values: Vec<MalType> = xs.iter().map(|x| eval(x.clone(), env)).collect();
                    if values.len() > 1 {
                        fun(values[1..].to_vec())
                    } else {
                        fun(vec![])
                    }
                },
                MalType::Symbol(s) if KEYWORDS.contains_key(&s) => {
                    KEYWORDS.get(&s).unwrap()(&xs, env)
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
