pub fn jsonToStruct(comptime T: type, json: []const u8) !T {
    var result: T = undefined;
    var i: usize = 0;
    var field_index: usize = 0;

    while (i < json.len) {
        skip_whitespace(json, &i);
        if (json[i] != '"') return error.InvalidJson;
        i += 1;

        const field_name = try parse_string(json, &i);
        skip_whitespace(json, &i);
        if (json[i] != ':') return error.InvalidJson;
        i += 1;

        const field_info = @typeInfo(T).@"struct".fields[field_index];
        switch (@typeInfo(field_info.field_type)) {
            .Int => {
                const value = try parse_number(json, &i, field_info.field_type);
                @field(&result, field_info.name) = value;
            },
            .Pointer => |ptr_info| {
                if (ptr_info.child != u8) return error.InvalidJson;
                const value = try parse_string(json, &i);
                @field(&result, field_info.name) = value;
            },
            else => return error.InvalidJson,
        }

        skip_whitespace(json, &i);
        if (i >= json.len or json[i] != ',') break;
        i += 1;

        field_index += 1;
    }

    if (field_index != @typeInfo(T).@"struct".fields.len)
        return error.MissingField;

    return result;
}

fn skip_whitespace(json: []const u8, i: *usize) void {
    while (i.* < json.len and (json[i.*] == ' ' or json[i.*] == '\n' or json[i.*] == '\t'))
        i.* += 1;
}

fn parse_string(json: []const u8, i: *usize) ![]const u8 {
    const start = i.*;
    while (i.* < json.len and json[i.*] != '"')
        i.* += 1;
    if (i.* >= json.len) return error.InvalidJson;
    const end = i.*;
    i.* += 1;
    return json[start..end];
}

fn parse_number(json: []const u8, i: *usize, comptime T: type) !T {
    const start = i.*;
    while (i.* < json.len and json[i.*] >= '0' and json[i.*] <= '9')
        i.* += 1;
    if (i.* == start) return error.InvalidJson;
    const num_str = json[start..i.*];
    const num = std.fmt.parseInt(T, num_str, 10) catch return error.InvalidNumber;
    return num;
}