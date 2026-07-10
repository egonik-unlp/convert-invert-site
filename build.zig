const std = @import("std");

// Build launcher for convert-invert-site.
//
//   zig build serve                 serve the built UI on 0.0.0.0:8080, proxy /api -> :3124
//   zig build serve -Dport=9000     pick a different port
//   zig build serve -Dbackend-port=3124
//   zig build serve -Dapi-key=XXXX  inject X-API-Key server-side (key stays off the browser)
//   zig build ui                    (re)build the frontend bundle via npm
//
// `serve` needs the backend reachable on 127.0.0.1:<backend-port> (e.g. from
// `docker compose up -d api db redis jaeger`) and the UI built (`zig build ui`).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const port = b.option(u16, "port", "Port to serve the UI on (default 8080)") orelse 8080;
    const backend_port = b.option(u16, "backend-port", "Backend API port to proxy /api to (default 3124)") orelse 3124;
    const api_key = b.option(
        []const u8,
        "api-key",
        "If set, inject this X-API-Key on proxied /api requests (keeps the key out of the browser bundle)",
    ) orelse "";

    const options = b.addOptions();
    options.addOption(u16, "port", port);
    options.addOption(u16, "backend_port", backend_port);
    options.addOption([]const u8, "api_key", api_key);
    options.addOption([]const u8, "dist_dir", b.pathFromRoot("convert-invert-frontend/dist"));

    const exe = b.addExecutable(.{
        .name = "relay-serve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/serve/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = options.createModule() },
            },
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    const serve_step = b.step("serve", "Serve the built UI on 0.0.0.0 and proxy /api to the backend (LAN-accessible)");
    serve_step.dependOn(&run.step);

    // `zig build ui` builds the frontend bundle (needs Node/npm). Set VITE_API_KEY in your
    // environment first if you prefer the key baked into the bundle over proxy injection.
    const ui = b.addSystemCommand(&.{ "npm", "--prefix", "convert-invert-frontend", "run", "build" });
    const ui_step = b.step("ui", "Build the frontend bundle (convert-invert-frontend/dist) via npm");
    ui_step.dependOn(&ui.step);
}
