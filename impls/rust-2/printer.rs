use std::collections::HashMap;

use crate::types::{MalHashable, MalType};

fn print_map(
    m: HashMap<MalHashable, MalType>,
    print_readably: bool,
) -> String {
    let mut s = String::from("{");
    s.push_str(
        &m
            .iter()
            .map(|(key, value)| {
                let key_str = pr_str(key.to_mal_type(), print_readably);
                let val_str = pr_str(value.clone(), print_readably);
                format!("{key_str} {val_str}")
            })
            .collect::<Vec<String>>()
            .join(" ")
    );
    s.push('}');
    s
}

fn print_vec(
    var: Vec<MalType>,
    open_char: char,
    close_char: char,
    print_readably: bool,
) -> String {
    let mut s = String::from(open_char);
    s.push_str(
        &var
            .iter()
            .map(|var| pr_str(var.clone(), print_readably))
            .collect::<Vec<String>>()
            .join(" ")
    );
    s.push(close_char);
    s
}

fn escape_str(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '"' => "\\\"".to_string(),
            '\n' => "\\n".to_string(),
            '\\' => "\\\\".to_string(),
            _ => c.to_string(),
        })
        .collect::<Vec<String>>()
        .join("")
}

pub fn pr_str(var: MalType, print_readably: bool) -> String {
    match var {
        MalType::String(s) => {
            if print_readably {
                let s = escape_str(&s);
                format!("\"{s}\"")
            } else {
                s.clone()
            }
        },
        MalType::Nil => "nil".to_string(),
        MalType::Int(i) => i.to_string(),
        MalType::Bool(b) => b.to_string(),
        MalType::List(list) => print_vec(list, '(', ')', print_readably),
        MalType::Vector(vec) => print_vec(vec, '[', ']', print_readably),
        MalType::Dict(m) => print_map(m, print_readably),
        MalType::Symbol(s) => s,
        MalType::KeyWord(s) => s,
        MalType::Error(s) => s,
        MalType::Function(_) => "#<function>".to_string(),
        MalType::Fn(fn_) => format!("#<function> args: {:#?}; body: {:#?}; env: {:#?}", fn_.args, fn_.body, fn_.env),
    }
}
