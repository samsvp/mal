use std::rc::Rc;
use std::cell::RefCell;
use std::collections::HashMap;

use crate::types::MalType;

#[derive(Debug,Clone)]
pub struct Env {
    pub data: HashMap<String, MalType>,
    pub outer: Option<Box<Env>>,
}

impl Env {
    pub fn new(outer: Option<&Self>) -> Self {
        Self {
            data: HashMap::new(),
            outer: outer.map(|o| Box::new(o.clone())),
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
