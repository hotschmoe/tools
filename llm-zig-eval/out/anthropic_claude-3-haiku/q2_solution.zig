const std = @import("std");

pub const MockSocket = struct {
    is_connected: bool,
    connection_thread: ?std.Thread,
    mutex: std.Thread.Mutex,

    pub fn init() MockSocket {
        return MockSocket {
            .is_connected = false,
            .connection_thread = null,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn connect(self: *MockSocket, address: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (std.mem.eql(u8, address, "bad_host")) {
            return error.ConnectionRefused;
        }

        self.connection_thread = try std.Thread.spawn(.{}, connectionThread, .{self});
        try self.connection_thread.?.detach();
    }

    pub fn isConnected(self: *MockSocket) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.is_connected;
    }

    pub fn waitForConnection(self: *MockSocket) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.connection_thread) |thread| {
            thread.join();
        }
    }

    pub fn deinit(self: *MockSocket) void {
        self.waitForConnection();
    }

    fn connectionThread(self: *MockSocket) void {
        std.Thread.sleep(100_000_000);

        self.mutex.lock();
        defer self.mutex.unlock();

        self.is_connected = true;
    }
};