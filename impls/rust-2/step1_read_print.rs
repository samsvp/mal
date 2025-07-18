mod reader;
mod printer;
mod types;

use rustyline::error::ReadlineError;
use rustyline::{DefaultEditor, Result};
use types::MalType;

fn read(val: &str) -> MalType {
    reader::read_str(val)
}

fn eval(val: MalType) -> MalType {
    val
}

fn print(val: MalType) -> MalType {
    val
}

fn rep(val: &str) -> MalType {
    print(eval(read(val)))
}

fn main() -> Result<()> {
    let mut rl = DefaultEditor::new()?;
    let _ = rl.load_history("history.txt");

    loop {
        let readline = rl.readline("user> ");
        match readline {
            Ok(line) => {
                let v = rep(&line);
                let _ = rl.add_history_entry(&line);
                println!("{:?}", v);
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
