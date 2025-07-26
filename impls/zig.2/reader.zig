const std = @import("std");
const MalType = @import("types.zig").MalType;

const pcre = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

const PCRE2_ZERO_TERMINATED = ~@as(pcre.PCRE2_SIZE, 0);

var g_regex: ?*pcre.pcre2_code_8 = null;

/// Wrapper that holds the raw tokens (strings) of a Lisp expression (which may not be valid).
const TokenList = struct {
    tokens: std.ArrayListUnmanaged([]const u8),

    pub fn init() TokenList {
        const tokens: std.ArrayListUnmanaged([]const u8) = .empty;
        return .{ .tokens = tokens };
    }

    pub fn append(self: *TokenList, allocator: std.mem.Allocator, token: []const u8) !void {
        const owned_token = try std.mem.Allocator.dupe(allocator, u8, token);
        try self.tokens.append(allocator, owned_token);
    }

    pub fn deinit(self: *TokenList, allocator: std.mem.Allocator) void {
        for (self.tokens.items) |token| {
            allocator.free(token);
        }
        self.tokens.deinit(allocator);
    }
};

/// A helper token reader.
pub const Reader = struct {
    token_list: TokenList,
    current: usize,

    pub fn next(self: *Reader) ?[]const u8 {
        if (self.token_list.tokens.items.len <= self.current) {
            return null;
        }
        self.current += 1;
        return self.token_list.tokens.items[self.current - 1];
    }

    pub fn peek(self: Reader) ?[]const u8 {
        if (self.token_list.tokens.items.len <= self.current) {
            return null;
        }
        return self.token_list.tokens.items[self.current];
    }
};

fn compile_regex() *pcre.pcre2_code_8 {
    if (g_regex) |r| {
        return r;
    }

    const pattern: [*]const u8 =
        \\[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)
    ;
    var errornumber: i32 = undefined;
    var erroroffset: usize = undefined;
    const regex = pcre.pcre2_compile_8(
        pattern,
        PCRE2_ZERO_TERMINATED,
        0,
        &errornumber,
        &erroroffset,
        null,
    );

    if (regex) |r| {
        g_regex = r;
        return r;
    }

    @panic("Failed to build regex!");
}

fn tokenize(
    subject: []const u8,
    allocator: std.mem.Allocator,
) !TokenList {
    const regex = compile_regex();

    const match_data = pcre.pcre2_match_data_create_from_pattern_8(regex, null);
    defer pcre.pcre2_match_data_free_8(match_data);

    var offset: usize = 0;
    var list: TokenList = .init();

    while (true) {
        const rc = pcre.pcre2_match_8(
            regex,
            subject.ptr,
            subject.len,
            offset,
            0,
            match_data,
            null,
        );

        if (rc <= 0) {
            if (rc == pcre.PCRE2_ERROR_NOMATCH) {
                break;
            } else {
                // finished
                return list;
            }
        }

        const ovector = pcre.pcre2_get_ovector_pointer_8(match_data);
        const start = ovector[0];
        const end = ovector[1];

        if (start == end) {
            // Zero-length match — avoid infinite loop
            offset += 1;
            continue;
        }

        if (rc >= 2) {
            // Group 0 is the entire match
            // Group 1 is the first capturing group (what we want)
            const group_start = ovector[2];
            const group_end = ovector[3];

            if (group_start != group_end) {
                try list.append(allocator, subject[group_start..group_end]);
            }
        }

        offset = end;
    }

    return list;
}

fn readAtom(
    allocator: std.mem.Allocator,
    reader: *Reader,
) error{
    EOFStringReadError,
    OutOfMemory,
}!MalType {
    const atom = reader.next().?;
    if (atom.len == 0) {
        return .nil;
    }

    return switch (atom[0]) {
        ':' => colon_blk: {
            const str = try std.mem.Allocator.dupe(allocator, u8, atom);
            break :colon_blk .{ .keyword = str };
        },
        '"' => str_blk: {
            if (atom.len < 2 or atom[atom.len - 1] != '"') {
                break :str_blk error.EOFStringReadError;
            }

            var backslash_amount: usize = 0;
            var i: usize = atom.len - 2;
            while (i != 0 and atom[i] == '\\') {
                i -= 1;
                backslash_amount += 1;
            }
            if (backslash_amount % 2 != 0) {
                break :str_blk error.EOFStringReadError;
            }
            const str = try MalType.String.initFrom(allocator, atom[1 .. atom.len - 1]);
            break :str_blk .{ .string = str };
        },
        else => blk: {
            const maybe_num = std.fmt.parseInt(i32, atom, 10) catch null;
            if (maybe_num) |num| {
                break :blk .{ .int = num };
            }
            const maybe_float = std.fmt.parseFloat(f32, atom) catch null;
            if (maybe_float) |float| {
                break :blk .{ .float = float };
            }

            if (atom.len == 3 and std.mem.eql(u8, atom, "nil")) {
                return .nil;
            }

            const atom_str = try std.mem.Allocator.dupe(allocator, u8, atom);
            break :blk .{ .symbol = atom_str };
        },
    };
}

const CollectionType = enum {
    list,
    vector,
};
fn readCollection(
    allocator: std.mem.Allocator,
    reader: *Reader,
    collection_type: CollectionType,
) error{
    EOFCollectionReadError,
    EOFStringReadError,
    OutOfMemory,
}!MalType {
    var list: std.ArrayListUnmanaged(MalType) = .empty;
    // TODO! some types may allocate memory that needs cleaning (e.g. a list inside a list allocates memory)
    errdefer list.deinit(allocator);

    const close_bracket = switch (collection_type) {
        .list => ")",
        .vector => "]",
    };
    _ = reader.next();
    while (reader.peek()) |token| {
        if (std.mem.eql(u8, token, close_bracket)) {
            _ = reader.next();
            return switch (collection_type) {
                .list => .{ .list = list },
                .vector => .{ .vector = list },
            };
        }
        const val = try readForm(allocator, reader);
        try list.append(allocator, val);
    }
    return error.EOFCollectionReadError;
}

fn readForm(allocator: std.mem.Allocator, reader: *Reader) !MalType {
    const maybe_token = reader.peek();
    if (maybe_token == null) {
        return .nil;
    }

    const token = maybe_token.?;
    if (token.len == 0) {
        return .nil;
    }

    return switch (token[0]) {
        '(' => try readCollection(allocator, reader, .list),
        '[' => try readCollection(allocator, reader, .vector),
        else => try readAtom(allocator, reader),
    };
}

/// Transforms a string into a lisp expression.
pub fn readStr(
    allocator: std.mem.Allocator,
    subject: []const u8,
) !MalType {
    var token_list = try tokenize(subject, allocator);
    defer token_list.deinit(allocator);

    var reader = Reader{
        .token_list = token_list,
        .current = 0,
    };

    return readForm(allocator, &reader);
}
