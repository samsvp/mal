use regex::Regex;
use once_cell::sync::Lazy;

use crate::types::MalType;

static RE: Lazy<Regex> = Lazy::new(
    || Regex::new(r##"[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)"##).unwrap()
);

struct Reader {
    tokens: Vec<String>,
    pos: usize,
}

impl Reader {
    pub fn peek(self: &Self) -> &str {
        &self.tokens[self.pos]
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

            MalType::Symbom(token.to_string())
        },
    }
}

fn read_list(reader: &mut Reader) -> MalType {
    fn parse(reader: &mut Reader, acc: &mut Vec<MalType>) -> MalType {
        match reader.peek() {
            ")" => {
                reader.next();
                MalType::List(acc.to_vec())
            },
            _ => {
                let v = read_form(reader);
                acc.push(v);
                parse(reader, acc)
            }
        }

    }
    parse(reader, &mut vec![])
}

fn read_form(reader: &mut Reader) -> MalType {
    let Some(token) = reader.next() else {
        return MalType::Nil;
    };

    match token {
        "(" => read_list(reader),
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
