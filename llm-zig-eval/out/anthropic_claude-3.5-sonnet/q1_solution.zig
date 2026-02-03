const std = @import("std");

pub const MiniArena = struct {
    buffer: [1024]u8,
    pos: usize,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .buffer = undefined,
            .pos = 0,
        };
    }

    pub fn alloc(self: *Self, size: usize) ![]u8 {
        // Calculate aligned position
        const align_mask = 8 - 1;
        const aligned_pos = (self.pos + align_mask) & ~align_mask;
        
        // Check if we have enough space
        if (aligned_pos + size > self.buffer.len) {
            return error.OutOfMemory;
        }

        // Update position and return slice
        const result = self.buffer[aligned_pos..aligned_pos + size];
        self.pos = aligned_pos + size;
        return result;
    }

    pub fn reset(self: *Self) void {
        self.pos = 0;
    }
};