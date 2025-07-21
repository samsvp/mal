mod reader;
mod printer;
mod types;
mod env;

use rustyline::error::ReadlineError;
use rustyline::{DefaultEditor, Result};
use types::{MalResult, MalType};

use crate::printer::pr_str;

fn read(val: &str) -> MalResult {
    reader::read_str(val)
}

fn eval(val: MalType) -> MalType {
    val
}

fn print(val: MalType) -> String {
    pr_str(val, true)
}

fn rep(val: &str) -> String {
    match read(val) {
        Ok(m) => print(eval(m)),
        Err(err) => format!("Parse error: {err}"),
    }
}

fn main() -> Result<()> {
    let mut rl = DefaultEditor::new()?;
    let _ = rl.load_history("history.txt");

    loop {
        let readline = rl.readline("user> ");
        match readline {
            Ok(line) => {
                let v = rep(&line);
                println!("{v}");
                let _ = rl.add_history_entry(&line);
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
