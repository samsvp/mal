use std::collections::HashMap;

use regex::Regex;
use once_cell::sync::Lazy;

use crate::types::{MalHashable, MalType, HashableConvertError};

enum ColType {
    List,
    Vec,
}

static RE: Lazy<Regex> = Lazy::new(
    || Regex::new(r##"[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)"##).unwrap()
);

struct Reader {
    tokens: Vec<String>,
    pos: usize,
}

impl Reader {
    pub fn peek(self: &Self) -> Option<&str> {
        if self.pos >= self.tokens.len() {
            return None;
        }
        Some(&self.tokens[self.pos])
    }

    pub fn next(self: &mut Self) -> Option<&str> {
        if self.pos >= self.tokens.len() {
            return None;
        }
        self.pos += 1;
        Some(&self.tokens[self.pos - 1])
    }
}

fn read_atom(token: &str) -> MalType {
    match token {
        "nil" => MalType::Nil,
        "false" => MalType::Bool(false),
        "true" => MalType::Bool(true),
        "" => MalType::Nil,
        _ => {
            if let Ok(i) = token.parse::<i64>() {
                return MalType::Int(i);
            }

            let chars = token.as_bytes();
            if chars[0] == b'"' {
                if token.len() < 2 || chars[chars.len() - 1] != b'"' {
                    return MalType::Error("EOF unclosed string.".to_string());
                }

                let mut backslash_amount = 0;
                let mut i = chars.len() - 2;
                while i != 0 && chars[i] == b'\\' {
                    i -= 1;
                    backslash_amount += 1;
                }
                if backslash_amount % 2 != 0 {
                    return MalType::Error("EOF unclosed string.".to_string());
                }
                return MalType::String(token.to_string());
            };
            MalType::Symbol(token.to_string())
        },
    }
}

fn read_dict(reader: &mut Reader) -> MalType {
    fn parse(reader: &mut Reader, acc: &mut Vec<MalType>) -> MalType {
        match reader.peek() {
            Some("{") => {
                reader.next();
                if acc.len() % 2 != 0 {
                    return MalType::Error("Hash map needs an even number of elements".to_string());
                }

                let result: Result<HashMap<_,_>, HashableConvertError> = acc
                    .chunks(2)
                    .try_fold(HashMap::with_capacity(acc.len()/2), |mut map, chunk| {
                        let key = chunk[0].clone();
                        let value = chunk[1].clone();
                        let hashable_key = MalHashable::to_hashable(key)?;
                        map.insert(hashable_key, value);
                        Ok(map)
                    });

                match result {
                    Ok(map) => MalType::Dict(map),
                    Err(e) => MalType::Error(e.to_string()),
                }
            },
            Some(_) => {
                let v = read_form(reader);
                acc.push(v);
                parse(reader, acc)
            },
            None => MalType::Error("EOF unmatched '}'".to_string())
        }
    }
    parse(reader, &mut vec![])
}

fn read_collection(reader: &mut Reader, col_type: ColType) -> MalType {
    fn parse(reader: &mut Reader, col_type: ColType, acc: &mut Vec<MalType>) -> MalType {
        let close = match col_type {
            ColType::List => ")",
            ColType::Vec => "]",
        };

        match reader.peek() {
            Some(char) if char == close => {
                reader.next();
                match col_type {
                    ColType::Vec => MalType::Vector(acc.to_vec()),
                    ColType::List => MalType::List(acc.to_vec()),
                }
            },
            Some(_) => {
                let v = read_form(reader);
                acc.push(v);
                parse(reader, col_type, acc)
            },
            None => MalType::Error(format!("EOF unmatched '{close}'"))
        }

    }
    parse(reader, col_type, &mut vec![])
}


fn read_vec(reader: &mut Reader) -> MalType {
    read_collection(reader, ColType::Vec)
}

fn read_list(reader: &mut Reader) -> MalType {
    read_collection(reader, ColType::List)
}

fn read_form(reader: &mut Reader) -> MalType {
    let Some(token) = reader.next() else {
        return MalType::Nil;
    };

    match token {
        "(" => read_list(reader),
        "[" => read_vec(reader),
        "{" => read_dict(reader),
        token => read_atom(token)
    }
}

fn tokenize(string: &str) -> Vec<String> {
    RE
        .captures_iter(string)
        .filter_map(|cap| cap.get(1).map(|m| m.as_str().to_string()))
        .collect()
}

pub fn read_str(string: &str) -> MalType {
    let tokens = tokenize(string);
    let mut reader = Reader { tokens, pos: 0 };
    read_form(&mut reader)
}
