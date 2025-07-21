use std::fmt;
use std::collections::HashMap;
use crate::env::Env;

pub type MalFunction = fn (Vec<MalType>) -> MalType;

static INVALID_ARGUMENT: &str = "Invalid argument";
static DIVISION_BY_ZERO: &str = "Division by zero";
pub fn invalid_argument_error(who: MalType) -> MalType {
    MalType::Error(format!("{INVALID_ARGUMENT}: {who:#?}"))
}
pub fn division_by_zero_error() -> MalType {
    MalType::Error(DIVISION_BY_ZERO.to_string())
}
pub fn invalid_parameter_length_error(got: usize, expected: usize) -> MalType {
    MalType::Error(
        format!("Invalid parameter length: got {got}, expected {expected}.")
    )
}

#[derive(Debug,Clone)]
pub struct MalFn {
    pub args: Vec<String>,
    pub body: Box<MalType>,
    pub env:  Option<Env>,
}

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
    Function(MalFunction),
    Fn(MalFn),
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
