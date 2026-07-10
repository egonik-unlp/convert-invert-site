//! relay-serve — a tiny static-file server + `/api` reverse proxy for the SyncDash UI.
//!
//! `zig build serve` binds 0.0.0.0 so you can open the dashboard from another machine on
//! the LAN. It serves the built frontend (`convert-invert-frontend/dist`) and transparently
//! proxies every `/api/*` request to the Rust backend (default 127.0.0.1:3124), so the whole
//! app lives behind a single origin — no CORS, no nginx, no Node needed to serve.
//!
//! Built directly on Linux syscalls (std.os.linux) to stay clear of the churn in Zig 0.16's
//! std.Io / std.net. Single-threaded, one request per connection (Connection: close) — plenty
//! for a personal LAN dashboard.
const std = @import("std");
const linux = std.os.linux;
const cfg = @import("config");

const BACKLOG: u32 = 128;
const HEAD_MAX: usize = 64 * 1024;
const FILE_MAX: usize = 32 * 1024 * 1024;
const RELAY_BUF: usize = 64 * 1024;
/// 127.0.0.1 stored in network byte order (little-endian memory layout of the u32).
const LOOPBACK: u32 = std.mem.nativeToBig(u32, 0x7f00_0001);

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("relay-serve: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

/// Linux syscalls return a usize where [-4095, -1] (as unsigned) encodes -errno.
fn failed(rc: usize) bool {
    return @as(isize, @bitCast(rc)) < 0;
}

/// Write all bytes to a socket. Uses MSG_NOSIGNAL so a disconnected client cannot
/// deliver SIGPIPE and kill the server.
fn writeAll(fd: i32, bytes: []const u8) bool {
    var off: usize = 0;
    while (off < bytes.len) {
        const rc = linux.sendto(fd, bytes.ptr + off, bytes.len - off, linux.MSG.NOSIGNAL, null, 0);
        if (failed(rc) or rc == 0) return false;
        off += rc;
    }
    return true;
}

fn openListenSocket(port: u16) i32 {
    const s = linux.socket(linux.AF.INET, linux.SOCK.STREAM, 0);
    if (failed(s)) fatal("socket() failed", .{});
    const fd: i32 = @intCast(s);
    const one: u32 = 1;
    _ = linux.setsockopt(fd, linux.SOL.SOCKET, linux.SO.REUSEADDR, @ptrCast(&one), @sizeOf(u32));
    var addr = linux.sockaddr.in{ .port = std.mem.nativeToBig(u16, port), .addr = 0 }; // 0.0.0.0
    if (failed(linux.bind(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.in))))
        fatal("bind() failed on port {d} — is it already in use?", .{port});
    if (failed(linux.listen(fd, BACKLOG))) fatal("listen() failed", .{});
    return fd;
}

fn connectBackend() ?i32 {
    const s = linux.socket(linux.AF.INET, linux.SOCK.STREAM, 0);
    if (failed(s)) return null;
    const fd: i32 = @intCast(s);
    var addr = linux.sockaddr.in{ .port = std.mem.nativeToBig(u16, cfg.backend_port), .addr = LOOPBACK };
    if (failed(linux.connect(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.in)))) {
        _ = linux.close(fd);
        return null;
    }
    return fd;
}

fn headerValue(head: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, head, "\r\n");
    _ = lines.next(); // request line
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " "), name))
            return std.mem.trim(u8, line[colon + 1 ..], " \t");
    }
    return null;
}

fn contentType(path: []const u8) []const u8 {
    const map = .{
        .{ ".html", "text/html; charset=utf-8" },
        .{ ".js", "text/javascript; charset=utf-8" },
        .{ ".mjs", "text/javascript; charset=utf-8" },
        .{ ".css", "text/css; charset=utf-8" },
        .{ ".json", "application/json; charset=utf-8" },
        .{ ".svg", "image/svg+xml" },
        .{ ".woff2", "font/woff2" },
        .{ ".woff", "font/woff" },
        .{ ".ttf", "font/ttf" },
        .{ ".png", "image/png" },
        .{ ".jpg", "image/jpeg" },
        .{ ".webp", "image/webp" },
        .{ ".ico", "image/x-icon" },
        .{ ".map", "application/json" },
        .{ ".txt", "text/plain; charset=utf-8" },
    };
    inline for (map) |entry| {
        if (std.mem.endsWith(u8, path, entry[0])) return entry[1];
    }
    return "application/octet-stream";
}

fn lastSegmentHasDot(path: []const u8) bool {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse 0;
    return std.mem.indexOfScalar(u8, path[slash..], '.') != null;
}

fn respondSimple(fd: i32, status: []const u8, body: []const u8) void {
    var buf: [256]u8 = undefined;
    const head = std.fmt.bufPrint(
        &buf,
        "HTTP/1.1 {s}\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ status, body.len },
    ) catch return;
    _ = writeAll(fd, head);
    _ = writeAll(fd, body);
}

fn readFile(a: std.mem.Allocator, path_z: [:0]const u8) ?[]u8 {
    const ofd_rc = linux.open(path_z.ptr, .{}, 0);
    if (failed(ofd_rc)) return null;
    const ofd: i32 = @intCast(ofd_rc);
    defer _ = linux.close(ofd);

    var cap: usize = 256 * 1024;
    var data = a.alloc(u8, cap) catch return null;
    var len: usize = 0;
    while (true) {
        if (len == cap) {
            if (cap >= FILE_MAX) return null;
            cap *= 2;
            const bigger = a.alloc(u8, cap) catch return null;
            @memcpy(bigger[0..len], data[0..len]);
            data = bigger;
        }
        const rc = linux.read(ofd, data.ptr + len, cap - len);
        if (failed(rc)) return null;
        if (rc == 0) break;
        len += rc;
    }
    return data[0..len];
}

fn serveStatic(a: std.mem.Allocator, cfd: i32, target: []const u8) void {
    var path = target;
    if (std.mem.indexOfScalar(u8, path, '?')) |q| path = path[0..q];
    if (std.mem.indexOf(u8, path, "..") != null) {
        respondSimple(cfd, "400 Bad Request", "bad path\n");
        return;
    }
    if (path.len == 0 or std.mem.eql(u8, path, "/")) path = "/index.html";

    const body = readFileAt(a, path) orelse blk: {
        // SPA fallback: unknown *routes* (no file extension) get index.html; missing assets 404.
        if (!lastSegmentHasDot(path)) {
            break :blk readFileAt(a, "/index.html") orelse null;
        }
        break :blk null;
    };
    const data = body orelse {
        respondSimple(cfd, "404 Not Found", "not found\n");
        return;
    };

    const ctype = contentType(path);
    const head = std.fmt.allocPrint(
        a,
        "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
        .{ ctype, data.len },
    ) catch return;
    _ = writeAll(cfd, head);
    _ = writeAll(cfd, data);
}

/// Reads `<dist_dir><rel>` (rel begins with '/'), building a null-terminated path.
fn readFileAt(a: std.mem.Allocator, rel: []const u8) ?[]u8 {
    const total = cfg.dist_dir.len + rel.len;
    const buf = a.alloc(u8, total + 1) catch return null;
    @memcpy(buf[0..cfg.dist_dir.len], cfg.dist_dir);
    @memcpy(buf[cfg.dist_dir.len..][0..rel.len], rel);
    buf[total] = 0;
    const path_z = buf[0..total :0];
    return readFile(a, path_z);
}

fn proxy(a: std.mem.Allocator, cfd: i32, head_buf: []const u8, head_end: usize) void {
    _ = a;
    const line_end = std.mem.indexOf(u8, head_buf, "\r\n") orelse return;
    const content_len: usize = if (headerValue(head_buf[0..head_end], "content-length")) |v|
        (std.fmt.parseInt(usize, v, 10) catch 0)
    else
        0;

    const ufd = connectBackend() orelse {
        respondSimple(cfd, "502 Bad Gateway", "backend unreachable\n");
        return;
    };
    defer _ = linux.close(ufd);

    // Rebuild the request head: keep the request line, drop hop-by-hop / auth headers we
    // manage ourselves, force Connection: close so we can detect end-of-response, and inject
    // X-API-Key when configured (keeps the secret server-side, out of the browser bundle).
    if (!writeAll(ufd, head_buf[0 .. line_end + 2])) return;
    var lines = std.mem.splitSequence(u8, head_buf[line_end + 2 .. head_end], "\r\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " ");
        if (std.ascii.eqlIgnoreCase(name, "connection")) continue;
        if (std.ascii.eqlIgnoreCase(name, "proxy-connection")) continue;
        if (cfg.api_key.len > 0 and std.ascii.eqlIgnoreCase(name, "x-api-key")) continue;
        if (!writeAll(ufd, line)) return;
        if (!writeAll(ufd, "\r\n")) return;
    }
    if (cfg.api_key.len > 0) {
        if (!writeAll(ufd, "X-API-Key: ")) return;
        if (!writeAll(ufd, cfg.api_key)) return;
        if (!writeAll(ufd, "\r\n")) return;
    }
    if (!writeAll(ufd, "Connection: close\r\n\r\n")) return;

    // Forward the body: what we already read, then whatever remains per Content-Length.
    const body_have = head_buf.len - head_end;
    if (body_have > 0 and !writeAll(ufd, head_buf[head_end..])) return;

    var buf: [RELAY_BUF]u8 = undefined;
    var remaining: usize = if (content_len > body_have) content_len - body_have else 0;
    while (remaining > 0) {
        const want = @min(remaining, buf.len);
        const rc = linux.read(cfd, &buf, want);
        if (failed(rc) or rc == 0) break;
        if (!writeAll(ufd, buf[0..rc])) return;
        remaining -= rc;
    }

    // Relay the backend response verbatim until it closes the connection.
    while (true) {
        const rc = linux.read(ufd, &buf, buf.len);
        if (failed(rc) or rc == 0) break;
        if (!writeAll(cfd, buf[0..rc])) break;
    }
}

fn handle(a: std.mem.Allocator, cfd: i32) void {
    const head = a.alloc(u8, HEAD_MAX) catch return;
    var total: usize = 0;
    var head_end: usize = 0;
    while (true) {
        const rc = linux.read(cfd, head.ptr + total, head.len - total);
        if (failed(rc) or rc == 0) return;
        total += rc;
        if (std.mem.indexOf(u8, head[0..total], "\r\n\r\n")) |idx| {
            head_end = idx + 4;
            break;
        }
        if (total == head.len) {
            respondSimple(cfd, "431 Request Header Fields Too Large", "header too large\n");
            return;
        }
    }

    const line_end = std.mem.indexOf(u8, head[0..total], "\r\n") orelse return;
    var it = std.mem.tokenizeScalar(u8, head[0..line_end], ' ');
    _ = it.next() orelse return; // method
    const target = it.next() orelse return;

    if (std.mem.startsWith(u8, target, "/api")) {
        proxy(a, cfd, head[0..total], head_end);
    } else {
        serveStatic(a, cfd, target);
    }
}

pub fn main() void {
    // Fail early with a clear message if the UI hasn't been built.
    {
        var probe = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer probe.deinit();
        if (readFileAt(probe.allocator(), "/index.html") == null) {
            fatal(
                "no built UI at {s}\n  Build it first:  zig build ui        (or: cd convert-invert-frontend && npm run build)",
                .{cfg.dist_dir},
            );
        }
    }

    const lfd = openListenSocket(cfg.port);
    std.debug.print(
        \\
        \\  relay-serve — SyncDash on your LAN
        \\  ----------------------------------
        \\  Listening : http://0.0.0.0:{d}
        \\  From this PC        : http://localhost:{d}
        \\  From another PC     : http://<this-machine-LAN-IP>:{d}   (find it with: hostname -I)
        \\  Proxying /api  ->   127.0.0.1:{d}
        \\  API key inject :    {s}
        \\  Serving dir    :    {s}
        \\
        \\  Backend services are started for you by `zig build serve` (docker compose).
        \\  Ctrl-C stops the UI server;  `zig build down`  stops the backend.
        \\
    , .{
        cfg.port,
        cfg.port,
        cfg.port,
        cfg.backend_port,
        if (cfg.api_key.len > 0) "on (server-side)" else "off (bundle must carry VITE_API_KEY)",
        cfg.dist_dir,
    });

    while (true) {
        const c = linux.accept(lfd, null, null);
        if (failed(c)) continue;
        const cfd: i32 = @intCast(c);
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        handle(arena.allocator(), cfd);
        arena.deinit();
        _ = linux.close(cfd);
    }
}
