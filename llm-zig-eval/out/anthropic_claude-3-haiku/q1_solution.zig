pub const MiniArena = struct {
    buffer: [1024]u8 = [_]u8{0} ** 1024,
    pos: usize = 0,

    pub fn init() MiniArena {
        return MiniArena{};
    }

    pub fn alloc(self: *MiniArena, size: usize) ![]u8 {
        const aligned_size = std.mem.alignForward(size, 8);
        if (self.pos + aligned_size > self.buffer.len) {
            return error.OutOfMemory;
        }
        const slice = self.buffer[self.pos .. self.pos + aligned_size];
        self.pos += aligned_size;
        return slice;
    }

    pub fn reset(self: *MiniArena) void {
        self.pos = 0;
    }
};