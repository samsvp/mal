#[derive(Debug,Clone)]
pub enum MalType {
    At,
    Nil,
    Bool(bool),
    Int(i64),
    Symbom(String),
    KeyWord(String),
    String(String),
    List(Vec<MalType>),
}
