#[derive(Debug,Clone)]
pub enum MalType {
    At,
    Nil,
    Bool(bool),
    Int(i64),
    Symbol(String),
    KeyWord(String),
    String(String),
    Error(String),
    List(Vec<MalType>),
    Dict(Vec<(MalType, MalType)>),
    Vector(Vec<MalType>),
}
