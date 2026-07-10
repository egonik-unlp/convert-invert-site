const std = @import("std");

// Build launcher for convert-invert-site.
//
//   zig build serve                 LAUNCH EVERYTHING: build UI, start the backend stack
//                                    (db, redis, jaeger, api, sharing), then serve the UI on
//                                    0.0.0.0:8080 and reverse-proxy /api -> 127.0.0.1:3124.
//   zig build serve -Dport=9000     pick a different LAN port
//   zig build serve -Dbackend-port=3124
//   zig build serve -Dapi-key=XXXX  also inject X-API-Key server-side (optional; the UI
//                                    bundle already carries VITE_API_KEY from .env)
//   zig build up                    just start the backend services
//   zig build ui                    just (re)build the frontend bundle
//   zig build down                  stop the backend services
//
// `serve` needs Zig 0.16+, Docker, Node, and a filled-in .env (the four credentials:
// USER_NAME / USER_PASSWORD / CLIENT_ID / CLIENT_SECRET). Everything else has defaults.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const port = b.option(u16, "port", "LAN port to serve the UI on (default 8080)") orelse 8080;
    const backend_port = b.option(u16, "backend-port", "Backend API port to proxy /api to (default 3124)") orelse 3124;
    const api_key = b.option(
        []const u8,
        "api-key",
        "If set, inject this X-API-Key on proxied /api requests (the UI bundle already carries VITE_API_KEY from .env)",
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

    // Build the frontend bundle, baking VITE_API_KEY from .env so the served app authenticates.
    const build_ui = b.addSystemCommand(&.{
        "bash", "-c",
        "set -a; [ -f .env ] && . ./.env; set +a; VITE_API_KEY=\"${API_KEY:-}\" npm --prefix convert-invert-frontend run build",
    });

    // Bring up the backend services (builds images on first run; reuses them afterwards). The
    // `slsk` service is the aioslsk Soulseek engine (search + download + share on one login);
    // the api delegates to it. The compose frontend container is excluded — this Zig launcher
    // serves the UI.
    const compose_up = b.addSystemCommand(&.{
        "docker", "compose", "up", "-d", "db", "redis", "jaeger", "slsk", "api",
    });

    // Ask the router (UPnP-IGD) to forward the Soulseek listen port so uploaders can connect
    // back for file transfers. Best-effort: prints a hint and no-ops if UPnP is unavailable.
    // (Won't help under ISP carrier-grade NAT, where inbound is blocked above your router.)
    const upnp = b.addSystemCommand(&.{
        "bash", "-c",
        "port=$(grep -E '^(WORKER_PORT_BASE|LISTEN_PORT)=' .env 2>/dev/null | head -1 | cut -d= -f2); python3 tools/upnp/forward.py \"${port:-41000}\"",
    });

    // The launcher (long-running). Runs after the UI is built, the backend is up, and the
    // router port is forwarded.
    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    run.step.dependOn(&build_ui.step);
    run.step.dependOn(&compose_up.step);
    run.step.dependOn(&upnp.step);

    const serve_step = b.step("serve", "Launch everything: build UI, start the backend stack, serve on 0.0.0.0 (LAN)");
    serve_step.dependOn(&run.step);

    const ui_step = b.step("ui", "Build the frontend bundle (bakes VITE_API_KEY from .env)");
    ui_step.dependOn(&build_ui.step);

    const up_step = b.step("up", "Start the backend services (db, redis, jaeger, api, sharing)");
    up_step.dependOn(&compose_up.step);

    const forward_step = b.step("forward", "Open the Soulseek listen port on your router via UPnP");
    forward_step.dependOn(&upnp.step);

    const compose_down = b.addSystemCommand(&.{ "docker", "compose", "down" });
    const down_step = b.step("down", "Stop the backend services");
    down_step.dependOn(&compose_down.step);
}
