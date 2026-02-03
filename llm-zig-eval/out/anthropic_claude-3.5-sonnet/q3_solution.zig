const std = @import("std");

pub fn jsonToStruct(comptime T: type, json: []const u8) !T {
    const info = @typeInfo(T).Struct;
    var result: T = undefined;
    var index: usize = 0;

    // Skip opening brace
    if (json[index] != '{') return error.InvalidJson;
    index += 1;

    // Track which fields we've found
    var found = [_]bool{false} ** info.fields.len;

    while (index < json.len) {
        // Skip whitespace
        while (index < json.len and std.ascii.isWhitespace(json[index])) : (index += 1) {}
        if (index >= json.len) return error.InvalidJson;

        // End of object
        if (json[index] == '}') {
            // Check all fields were found
            for (found) |field_found| {
                if (!field_found) return error.MissingField;
            }
            return result;
        }

        // Parse field name
        if (json[index] != '"') return error.InvalidJson;
        index += 1;
        const name_start = index;
        while (index < json.len and json[index] != '"') : (index += 1) {}
        if (index >= json.len) return error.InvalidJson;
        const field_name = json[name_start..index];
        index += 1;

        // Skip whitespace and colon
        while (index < json.len and std.ascii.isWhitespace(json[index])) : (index += 1) {}
        if (index >= json.len or json[index] != ':') return error.InvalidJson;
        index += 1;
        while (index < json.len and std.ascii.isWhitespace(json[index])) : (index += 1) {}

        // Find matching field
        inline for (info.fields, 0..) |field, i| {
            if (std.mem.eql(u8, field.name, field_name)) {
                found[i] = true;
                
                // Parse value based on field type
                switch (@typeInfo(field.type)) {
                    .Int => |int_info| {
                        const num_start = index;
                        while (index < json.len and (std.ascii.isDigit(json[index]) or json[index] == '-')) : (index += 1) {}
                        const num_str = json[num_start..index];
                        
                        if (int_info.signedness == .signed) {
                            @field(result, field.name) = std.fmt.parseInt(field.type, num_str, 10) catch return error.InvalidNumber;
                        } else {
                            @field(result, field.name) = std.fmt.parseUnsigned(field.type, num_str, 10) catch return error.InvalidNumber;
                        }
                    },
                    .Pointer => |ptr_info| {
                        if (ptr_info.size != .Slice or ptr_info.child != u8) {
                            @compileError("Only []const u8 strings are supported");
                        }
                        if (json[index] != '"') return error.InvalidJson;
                        index += 1;
                        const str_start = index;
                        while (index < json.len and json[index] != '"') : (index += 1) {}
                        if (index >= json.len) return error.InvalidJson;
                        @field(result, field.name) = json[str_start..index];
                        index += 1;
                    },
                    else => @compileError("Unsupported field type"),
                }
                break;
            }
        }

        // Skip whitespace and comma
        while (index < json.len and std.ascii.isWhitespace(json[index])) : (index += 1) {}
        if (index < json.len and json[index] == ',') {
            index += 1;
            continue;
        }
    }

    return error.InvalidJson;
}