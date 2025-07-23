use std::collections::HashMap;

use regex::Regex;
use once_cell::sync::Lazy;

use crate::types::{MalError, MalFn, MalHashable, MalResult, MalType};

static RE: Lazy<Regex> = Lazy::new(
    || Regex::new(r##"[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)"##).unwrap()
);

enum ColType {
    List,
    Vec,
}

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

fn read_atom(token: &str) -> MalResult {
    match token {
        "nil" => Ok(MalType::Nil),
        "false" => Ok(MalType::Bool(false)),
        "true" => Ok(MalType::Bool(true)),
        "" => Ok(MalType::Nil),
        _ => {
            if let Ok(i) = token.parse::<i64>() {
                return Ok(MalType::Int(i));
            }

            let chars = token.as_bytes();
            if chars[0] == b'"' {
                if token.len() < 2 || chars[chars.len() - 1] != b'"' {
                    return Err(MalError::new("EOF unclosed string.".to_string()));
                }

                let mut backslash_amount = 0;
                let mut i = chars.len() - 2;
                while i != 0 && chars[i] == b'\\' {
                    i -= 1;
                    backslash_amount += 1;
                }
                if backslash_amount % 2 != 0 {
                    return Err(MalError::new("EOF unclosed string.".to_string()));
                }
                return Ok(MalType::String(token[1..token.len()-1].to_string()));
            } else if chars[0] == b':' {
                return Ok(MalType::KeyWord(token.to_string()));
            }
            Ok(MalType::Symbol(token.to_string()))
        },
    }
}

fn read_dict(reader: &mut Reader) -> MalResult {
    fn parse(reader: &mut Reader, acc: &mut Vec<MalType>) -> MalResult {
        match reader.peek() {
            Some("}") => {
                reader.next();
                if acc.len() % 2 != 0 {
                    return Err(MalError::new("Hash map needs an even number of elements".to_string()));
                }

                let map: HashMap<_,_> = acc
                    .chunks(2)
                    .try_fold(HashMap::with_capacity(acc.len()/2), |mut map, chunk| {
                        let key = chunk[0].clone();
                        let value = chunk[1].clone();
                        let hashable_key = MalHashable::to_hashable(key)?;
                        map.insert(hashable_key, value);
                        Ok(map)
                    })?;

                Ok(MalType::Dict(map))
            },
            Some(_) => {
                let v = read_form(reader)?;
                acc.push(v);
                parse(reader, acc)
            },
            None => Err(MalError::new("EOF unmatched '}'".to_string()))
        }
    }
    parse(reader, &mut vec![])
}

fn read_collection(reader: &mut Reader, col_type: ColType) -> MalResult {
    fn parse(reader: &mut Reader, col_type: ColType, acc: &mut Vec<MalType>) -> MalResult {
        let close = match col_type {
            ColType::List => ")",
            ColType::Vec => "]",
        };

        match reader.peek() {
            Some(char) if char == close => {
                reader.next();
                match col_type {
                    ColType::Vec => Ok(MalType::Vector(acc.to_vec())),
                    ColType::List => Ok(MalType::List(acc.to_vec())),
                }
            },
            Some(_) => {
                let v = read_form(reader)?;
                acc.push(v);
                parse(reader, col_type, acc)
            },
            None => Err(MalError::new(format!("EOF unmatched '{close}'")))
        }

    }
    parse(reader, col_type, &mut vec![])
}


fn read_vec(reader: &mut Reader) -> MalResult {
    read_collection(reader, ColType::Vec)
}

fn read_list(reader: &mut Reader) -> MalResult {
    read_collection(reader, ColType::List)
}

fn read_fn(reader: &mut Reader) -> MalResult {
    let mut is_variadic = false;
    let args =
        match read_form(reader)? {
            MalType::List(args) | MalType::Vector(args) => {
                args.iter().enumerate().try_fold(Vec::with_capacity(args.len()), |mut acc, (i, x)|
                    match x {
                        MalType::Symbol(s) if s == "&" => {
                            if i != args.len() - 2 {
                                return Err(MalError::new("Variadic argument must be the last".to_string()));
                            }
                            is_variadic = true;
                            Ok(acc)
                        },
                        MalType::Symbol(s) => {
                            acc.push(s.to_string());
                            Ok(acc)
                        },
                        _ => Err(MalError::new("Function parameters must be symbols.".to_string())),
                    })
            },
            _ => Err(MalError::new("Function arguments must list.".to_string())),
        }?;

    let body = read_form(reader)?;
    reader.next();
    Ok(MalType::Fn(MalFn {args, body: Box::new(body), env: None, is_variadic}))
}

fn read_form(reader: &mut Reader) -> MalResult {
    let Some(token) = reader.next() else {
        return Ok(MalType::Nil);
    };

    match token {
        "(" => {
            match reader.peek() {
                Some("fn*") => {
                    reader.next();
                    read_fn(reader)
                },
                Some(_) => read_list(reader),
                _ => Err(MalError::new("EOF unmatched ')'".to_string())),
            }
        },
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

pub fn read_str(string: &str) -> MalResult {
    let tokens = tokenize(string);
    let mut reader = Reader { tokens, pos: 0 };
    read_form(&mut reader)
}
