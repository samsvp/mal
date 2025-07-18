use std::fmt;
use std::collections::HashMap;

#[derive(Debug,Clone)]
pub enum MalType {
    Nil,
    Bool(bool),
    Int(i64),
    Symbol(String),
    KeyWord(String),
    String(String),
    Error(String),
    List(Vec<MalType>),
    Dict(HashMap<MalHashable, MalType>),
    Vector(Vec<MalType>),
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum MalHashable {
    Nil,
    Bool(bool),
    Int(i64),
    Symbol(String),
    KeyWord(String),
    String(String),
}

#[derive(Debug,Clone)]
pub struct HashableConvertError;
impl fmt::Display for HashableConvertError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Value is not hashable.")
    }
}

impl MalHashable {
    pub fn to_hashable(t: MalType) -> Result<MalHashable, HashableConvertError> {
        match t {
            MalType::Nil => Ok(MalHashable::Nil),
            MalType::Int(i) => Ok(MalHashable::Int(i)),
            MalType::Bool(b) => Ok(MalHashable::Bool(b)),
            MalType::Symbol(s) => Ok(MalHashable::Symbol(s)),
            MalType::String(s) => Ok(MalHashable::String(s)),
            MalType::KeyWord(s) => Ok(MalHashable::KeyWord(s)),
            _ => Err(HashableConvertError),
        }
    }

    pub fn to_mal_type(self: &Self) -> MalType {
        match self {
            MalHashable::Nil => MalType::Nil,
            MalHashable::String(s) => MalType::String(s.to_string()),
            MalHashable::Symbol(s) => MalType::Symbol(s.to_string()),
            MalHashable::KeyWord(s) => MalType::KeyWord(s.to_string()),
            MalHashable::Bool(b) => MalType::Bool(*b),
            MalHashable::Int(i) => MalType::Int(*i),
        }
    }
}
