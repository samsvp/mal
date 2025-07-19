use std::collections::HashMap;

use crate::types::MalType;

#[derive(Debug,Clone)]
pub struct Env<'a> {
    data: HashMap<String, MalType>,
    outer: Option<Box<&'a Env<'a>>>,
}

impl<'a> Env<'a> {
    pub fn new(outer: Option<&'a Env<'a>>) -> Self {
        Self {
            data: HashMap::new(),
            outer: outer.map(|o| Box::new(o)),
        }
    }

    pub fn from(data: HashMap<String, MalType>) -> Self {
        Self {
            data,
            outer: None,
        }
    }

    pub fn set(&mut self, key: String, value: MalType) {
        self.data.insert(key, value);
    }

    pub fn get(&self, key: String) -> Option<MalType> {
        self.data.get(&key).cloned().or(
            self.outer.as_ref().map_or(None, |o| o.get(key))
        )
    }
}
