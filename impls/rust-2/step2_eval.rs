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

fn eval(val: MalType, env: &Env) -> MalType {
    match val {
        MalType::Symbol(s) => {
            let Some(v) = env.get(s) else {
                return MalType::Error("Symbol not found".to_string());
            };
            v.clone()
        },
        MalType::List(xs) => {
            if xs.len() == 0 {
                return MalType::List(vec![]);
            }

            let values: Vec<MalType> = xs.into_iter().map(|x| eval(x, env)).collect();
            match values[0] {
                MalType::Function(fun) => {
                    if values.len() > 1 {
                        fun(values[1..].to_vec())
                    } else {
                        fun(vec![])
                    }
                }
                _ => {
                    MalType::List(values)
                }
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

fn rep(val: &str, env: &Env) -> MalType {
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

    let env = get_env();

    loop {
        let readline = rl.readline("user> ");
        match readline {
            Ok(line) => {
                let v = rep(&line, &env);
                let _ = rl.add_history_entry(&line);
                let v = pr_str(v, true);
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
