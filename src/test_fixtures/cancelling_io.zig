//! A real filesystem `std.Io` whose nth call of one operation class observes a cancellation request.
//! Every other call, and every call after the cancelled one, runs on the real threaded `Io`.
const std = @import("std");

const Io = std.Io;

pub const Op = enum { none, open_file, create_file, delete_file, open_dir, create_dir, real_path_file, dir_access, dir_read, dir_stat, stat_file, stat, write_positional, write_streaming, read_positional, sync, set_length, try_lock, random_secure };

pub const CancellingIo = struct {
    threaded: Io.Threaded,
    vtable: Io.VTable,
    real: *const Io.VTable,
    op: Op,
    /// Calls of `op` that pass before the next one is cancelled.
    pass: usize,
    fired: bool = false,

    pub fn init(self: *CancellingIo, op: Op, pass: usize) void {
        self.* = .{ .threaded = .init(std.testing.allocator, .{}), .vtable = undefined, .real = undefined, .op = op, .pass = pass };
        self.real = self.threaded.io().vtable;
        self.vtable = self.real.*;
        self.vtable.dirOpenFile = openFile;
        self.vtable.dirCreateFile = createFile;
        self.vtable.dirDeleteFile = deleteFile;
        self.vtable.dirOpenDir = openDir;
        self.vtable.dirCreateDir = createDir;
        self.vtable.dirRealPathFile = realPathFile;
        self.vtable.dirAccess = dirAccess;
        self.vtable.dirRead = dirRead;
        self.vtable.dirStat = dirStat;
        self.vtable.dirStatFile = statFile;
        self.vtable.randomSecure = randomSecure;
        self.vtable.fileStat = stat;
        self.vtable.fileWritePositional = writePositional;
        self.vtable.fileReadPositional = readPositional;
        self.vtable.fileSync = sync;
        self.vtable.fileSetLength = setLength;
        self.vtable.fileTryLock = tryLock;
        self.vtable.operate = operate;
    }

    pub fn deinit(self: *CancellingIo) void {
        self.threaded.deinit();
    }

    pub fn io(self: *CancellingIo) Io {
        return .{ .userdata = &self.threaded, .vtable = &self.vtable };
    }

    /// Whether this call of `op` is the one that observes the cancellation.
    fn fires(self: *CancellingIo, op: Op) bool {
        if (self.op != op or self.fired) return false;
        if (self.pass > 0) {
            self.pass -= 1;
            return false;
        }
        self.fired = true;
        return true;
    }
};

/// Runs `attempt` once for each call of `op` it makes, cancelling that call, then once with nothing
/// cancelled. Every cancelled run must report `error.Cancelled`, whatever the rest of the call is: a fault
/// of another kind is a collapsed cancellation. The result is how many calls of `op` the attempt makes, so
/// a caller can require that the class is reached at all.
pub fn sweep(op: Op, context: anytype, comptime attempt: fn (@TypeOf(context), Io) anyerror!void) !usize {
    var pass: usize = 0;
    while (true) : (pass += 1) {
        var cancel: CancellingIo = undefined;
        cancel.init(op, pass);
        defer cancel.deinit();
        const result = attempt(context, cancel.io());
        if (!cancel.fired) {
            try result;
            return pass;
        }
        std.testing.expectError(error.Cancelled, result) catch |err| {
            std.debug.print("the {s} call after {d} others of its class did not end the attempt cancelled\n", .{ @tagName(op), pass });
            return err;
        };
    }
}

fn cast(context: ?*anyopaque) *CancellingIo {
    const threaded: *Io.Threaded = @ptrCast(@alignCast(context.?));
    return @fieldParentPtr("threaded", threaded);
}

fn openFile(context: ?*anyopaque, dir: Io.Dir, path: []const u8, options: Io.Dir.OpenFileOptions) Io.File.OpenError!Io.File {
    const self = cast(context);
    if (self.fires(.open_file)) return error.Canceled;
    return self.real.dirOpenFile(context, dir, path, options);
}

fn createFile(context: ?*anyopaque, dir: Io.Dir, path: []const u8, options: Io.Dir.CreateFileOptions) Io.File.OpenError!Io.File {
    const self = cast(context);
    if (self.fires(.create_file)) return error.Canceled;
    return self.real.dirCreateFile(context, dir, path, options);
}

fn deleteFile(context: ?*anyopaque, dir: Io.Dir, path: []const u8) Io.Dir.DeleteFileError!void {
    const self = cast(context);
    if (self.fires(.delete_file)) return error.Canceled;
    return self.real.dirDeleteFile(context, dir, path);
}

fn openDir(context: ?*anyopaque, dir: Io.Dir, path: []const u8, options: Io.Dir.OpenOptions) Io.Dir.OpenError!Io.Dir {
    const self = cast(context);
    if (self.fires(.open_dir)) return error.Canceled;
    return self.real.dirOpenDir(context, dir, path, options);
}

fn createDir(context: ?*anyopaque, dir: Io.Dir, path: []const u8, permissions: Io.Dir.Permissions) Io.Dir.CreateDirError!void {
    const self = cast(context);
    if (self.fires(.create_dir)) return error.Canceled;
    return self.real.dirCreateDir(context, dir, path, permissions);
}

fn realPathFile(context: ?*anyopaque, dir: Io.Dir, path: []const u8, out_buffer: []u8) Io.Dir.RealPathFileError!usize {
    const self = cast(context);
    if (self.fires(.real_path_file)) return error.Canceled;
    return self.real.dirRealPathFile(context, dir, path, out_buffer);
}

fn dirAccess(context: ?*anyopaque, dir: Io.Dir, path: []const u8, options: Io.Dir.AccessOptions) Io.Dir.AccessError!void {
    const self = cast(context);
    if (self.fires(.dir_access)) return error.Canceled;
    return self.real.dirAccess(context, dir, path, options);
}

fn dirRead(context: ?*anyopaque, reader: *Io.Dir.Reader, entries: []Io.Dir.Entry) Io.Dir.Reader.Error!usize {
    const self = cast(context);
    if (self.fires(.dir_read)) return error.Canceled;
    return self.real.dirRead(context, reader, entries);
}

fn dirStat(context: ?*anyopaque, dir: Io.Dir) Io.Dir.StatError!Io.Dir.Stat {
    const self = cast(context);
    if (self.fires(.dir_stat)) return error.Canceled;
    return self.real.dirStat(context, dir);
}

fn statFile(context: ?*anyopaque, dir: Io.Dir, path: []const u8, options: Io.Dir.StatFileOptions) Io.Dir.StatFileError!Io.File.Stat {
    const self = cast(context);
    if (self.fires(.stat_file)) return error.Canceled;
    return self.real.dirStatFile(context, dir, path, options);
}

fn randomSecure(context: ?*anyopaque, buffer: []u8) Io.RandomSecureError!void {
    const self = cast(context);
    if (self.fires(.random_secure)) return error.Canceled;
    return self.real.randomSecure(context, buffer);
}

fn stat(context: ?*anyopaque, file: Io.File) Io.File.StatError!Io.File.Stat {
    const self = cast(context);
    if (self.fires(.stat)) return error.Canceled;
    return self.real.fileStat(context, file);
}

fn writePositional(context: ?*anyopaque, file: Io.File, header: []const u8, data: []const []const u8, splat: usize, offset: u64) Io.File.WritePositionalError!usize {
    const self = cast(context);
    if (self.fires(.write_positional)) return error.Canceled;
    return self.real.fileWritePositional(context, file, header, data, splat, offset);
}

fn readPositional(context: ?*anyopaque, file: Io.File, data: []const []u8, offset: u64) Io.File.ReadPositionalError!usize {
    const self = cast(context);
    if (self.fires(.read_positional)) return error.Canceled;
    return self.real.fileReadPositional(context, file, data, offset);
}

fn sync(context: ?*anyopaque, file: Io.File) Io.File.SyncError!void {
    const self = cast(context);
    if (self.fires(.sync)) return error.Canceled;
    return self.real.fileSync(context, file);
}

fn setLength(context: ?*anyopaque, file: Io.File, length: u64) Io.File.SetLengthError!void {
    const self = cast(context);
    if (self.fires(.set_length)) return error.Canceled;
    return self.real.fileSetLength(context, file, length);
}

fn tryLock(context: ?*anyopaque, file: Io.File, lock: Io.File.Lock) Io.File.LockError!bool {
    const self = cast(context);
    if (self.fires(.try_lock)) return error.Canceled;
    return self.real.fileTryLock(context, file, lock);
}

/// Streaming file writes reach the `Io` as an operation.
fn operate(context: ?*anyopaque, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
    const self = cast(context);
    if (operation == .file_write_streaming and self.fires(.write_streaming)) return error.Canceled;
    return self.real.operate(context, operation);
}
