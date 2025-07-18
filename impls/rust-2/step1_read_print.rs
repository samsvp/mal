mod reader;
mod printer;

use rustyline::error::ReadlineError;
use rustyline::{DefaultEditor, Result};

fn read(val: &str) -> Vec<String> {
    reader::read_str(val)
}

fn eval(val: Vec<String>) -> Vec<String> {
    val
}

fn print(val: Vec<String>) -> Vec<String> {
    val
}

fn rep(val: &str) -> Vec<String> {
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
