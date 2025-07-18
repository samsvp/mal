use std::collections::HashMap;

use crate::types::{MalHashable, MalType};

fn print_map(m: HashMap<MalHashable, MalType>) -> String {
    let mut s = String::from("{");
    s.push_str(
        &m
            .iter()
            .map(|(key, value)| {
                let key_str = pr_str(key.to_mal_type());
                let val_str = pr_str(value.clone());
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
) -> String {
    let mut s = String::from(open_char);
    s.push_str(
        &var
            .iter()
            .map(|var| pr_str(var.clone()))
            .collect::<Vec<String>>()
            .join(" ")
    );
    s.push(close_char);
    s
}

pub fn pr_str(var: MalType) -> String {
    match var {
        MalType::String(s) => s,
        MalType::Nil => "nil".to_string(),
        MalType::Int(i) => i.to_string(),
        MalType::Bool(b) => b.to_string(),
        MalType::List(list) => print_vec(list, '(', ')'),
        MalType::Vector(vec) => print_vec(vec, '[', ']'),
        MalType::Dict(m) => print_map(m),
        MalType::Symbol(s) => s,
        MalType::KeyWord(s) => s,
        MalType::Error(s) => s,
    }
}
