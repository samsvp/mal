use regex::Regex;
use once_cell::sync::Lazy;

use crate::types::MalType;

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
        "@" => MalType::At,
        "nil" => MalType::Nil,
        "false" => MalType::Bool(false),
        "true" => MalType::Bool(true),
        "" => MalType::Nil,
        _ => {
            if let Ok(i) = token.parse::<i64>() {
                return MalType::Int(i);
            }

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
                MalType::Dict(
                    acc.chunks(2).map(|chunk| (chunk[0].clone(), chunk[1].clone())).collect()
                )
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
