const std = @import("std");

pub const MockSocket = struct {
    connected: bool,
    thread: ?std.Thread,
    mutex: std.Thread.Mutex,
    
    const Self = @This();

    pub fn init() Self {
        return Self{
            .connected = false,
            .thread = null,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn connect(self: *Self, address: []const u8) !void {
        if (std.mem.eql(u8, address, "bad_host")) {
            return error.ConnectionRefused;
        }

        self.thread = try std.Thread.spawn(.{}, connectThread, .{ self, address });
    }

    fn connectThread(self: *Self, address: []const u8) void {
        std.time.sleep(100 * std.time.ns_per_ms);
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.connected = true;
    }

    pub fn isConnected(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.connected;
    }

    pub fn waitForConnection(self: *Self) void {
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.thread) |thread| {
            thread.join();
        }
    }
};