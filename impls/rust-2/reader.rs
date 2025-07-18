use regex::Regex;
use once_cell::sync::Lazy;

static RE: Lazy<Regex> = Lazy::new(
    || Regex::new(r##"[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)"##).unwrap()
);

struct Reader {
    tokens: Vec<String>,
    pos: u64,
}

impl Reader {
}


pub fn tokenize(string: &str) -> Vec<String> {
    RE
        .find_iter(string)
        .map(|m| m.as_str().to_string())
        .collect()
}

pub fn read_str(string: &str) -> Vec<String> {
    tokenize(string)
}
