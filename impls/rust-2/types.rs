use std::{collections::HashMap, hash::{Hash,Hasher}};

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
    Dict(HashMap<MalType, MalType>),
    Vector(Vec<MalType>),
}

impl Hash for MalType {
    fn hash<H: Hasher>(&self, state: &mut H) {
        match self {
            MalType::At => 0.hash(state),
            MalType::Nil => 1.hash(state),
            MalType::Bool(b) => {
                2.hash(state);
                b.hash(state)
            }
            MalType::Int(i) => {
                3.hash(state);
                i.hash(state)
            }
            MalType::Symbol(s) => {
                4.hash(state);
                s.hash(state)
            }
            MalType::KeyWord(s) => {
                5.hash(state);
                s.hash(state)
            }
            MalType::String(s) => {
                6.hash(state);
                s.hash(state)
            }
            MalType::Error(s) => {
                7.hash(state);
                s.hash(state)
            }
            MalType::List(v) => {
                8.hash(state);
                v.len().hash(state);
                for item in v {
                    item.hash(state);
                }
            }
            MalType::Dict(map) => {
                9.hash(state);
                // Hash the number of entries
                map.len().hash(state);
                // Hash all keys and values in a deterministic way
                let mut entries: Vec<_> = map.iter().collect();
                entries.sort_by(|a, b| {
                    // Compare hash of keys (not perfect, but best-effort)
                    let mut a_hash = std::collections::hash_map::DefaultHasher::new();
                    a.0.hash(&mut a_hash);
                    let a_hash = a_hash.finish();

                    let mut b_hash = std::collections::hash_map::DefaultHasher::new();
                    b.0.hash(&mut b_hash);
                    let b_hash = b_hash.finish();

                    a_hash.cmp(&b_hash)
                });
                for (k, v) in entries {
                    k.hash(state);
                    v.hash(state);
                }
            }
            MalType::Vector(v) => {
                10.hash(state);
                v.len().hash(state);
                for item in v {
                    item.hash(state);
                }
            }
        }
    }
}

impl PartialEq for MalType {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (MalType::At, MalType::At) => true,
            (MalType::Nil, MalType::Nil) => true,
            (MalType::Bool(a), MalType::Bool(b)) => a == b,
            (MalType::Int(a), MalType::Int(b)) => a == b,
            (MalType::Symbol(a), MalType::Symbol(b)) => a == b,
            (MalType::KeyWord(a), MalType::KeyWord(b)) => a == b,
            (MalType::String(a), MalType::String(b)) => a == b,
            (MalType::Error(a), MalType::Error(b)) => a == b,
            (MalType::List(a), MalType::List(b)) => a == b,
            (MalType::Dict(a), MalType::Dict(b)) => a == b,
            (MalType::Vector(a), MalType::Vector(b)) => a == b,
            _ => false,
        }
    }
}

impl Eq for MalType {}
