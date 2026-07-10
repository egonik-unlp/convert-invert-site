const std = @import("std");

// Build launcher for convert-invert-site.
//
//   zig build serve                 LAUNCH EVERYTHING: start the full docker stack (db, redis,
//                                    jaeger, slsk, api, and the frontend UI on :5173), forward
//                                    the Soulseek port, and print the LAN dashboard URL.
//   zig build up                    start the full docker stack (same, without UPnP)
//   zig build ui                    (optional) build a standalone frontend bundle
//   zig build down                  stop the docker stack
//
// The dashboard is served by the docker `frontend` container (:5173) — it is the single UI,
// reachable from any machine on the LAN. There is no separate Zig-served copy.
//
// `serve` needs Zig 0.16+, Docker, Node, and a filled-in .env (the four credentials:
// USER_NAME / USER_PASSWORD / CLIENT_ID / CLIENT_SECRET). Everything else has defaults.
//
// The backend stack lives at /srv/storage/docker/convert-invert (the boot deployment that
// auto-starts via `restart: unless-stopped`), so `up`/`serve`/`down` reuse those containers
// instead of launching a conflicting second copy from this repo's docker-compose.yml.
const boot_dir = "/srv/storage/docker/convert-invert";
const boot_compose = boot_dir ++ "/docker-compose.yml";

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
    const sync_playlist = b.option([]const u8, "playlist", "Spotify playlist URL or ID to sync (for `zig build sync`)") orelse "";
    const sync_workers = b.option(u16, "workers", "Workers for `zig build sync` (default 1)") orelse 1;
    const sync_chunk = b.option(u16, "chunk", "Chunk size for `zig build sync` (default 15)") orelse 15;

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

    // Bring up the WHOLE stack, including the `frontend` container — the dashboard on :5173 is
    // the single canonical UI (LAN-accessible via its docker port mapping). The `slsk` service
    // is the aioslsk Soulseek engine (search + download + share on one login); the api delegates
    // to it.
    const compose_up = b.addSystemCommand(&.{
        "docker", "compose", "--project-directory", boot_dir,   "-f",  boot_compose,
        "up",     "-d",      "db",                  "redis",     "jaeger", "slsk",
        "api",    "frontend",
    });

    // Print the LAN URL of the docker frontend so it's easy to open from another machine.
    const announce = b.addSystemCommand(&.{
        "bash", "-c",
        "set -a; [ -f .env ] && . ./.env; set +a; ip=$(hostname -I 2>/dev/null | awk '{print $1}'); echo; echo \"  Dashboard: http://${ip:-localhost}:${FRONTEND_PORT:-5173}  (open from any machine on your LAN)\"; echo",
    });
    announce.step.dependOn(&compose_up.step);

    // Ask the router (UPnP-IGD) to forward the Soulseek listen port so uploaders can connect
    // back for file transfers. Best-effort: prints a hint and no-ops if UPnP is unavailable.
    // (Won't help under ISP carrier-grade NAT, where inbound is blocked above your router.)
    const upnp = b.addSystemCommand(&.{
        "bash", "-c",
        "port=$(grep -E '^(WORKER_PORT_BASE|LISTEN_PORT)=' .env 2>/dev/null | head -1 | cut -d= -f2); python3 tools/upnp/forward.py \"${port:-41000}\"",
    });

    // `zig build serve` = launch the whole docker stack (incl. the frontend UI on :5173),
    // forward the Soulseek port, and print the LAN URL. The dashboard is served by the docker
    // `frontend` container — there is no separate Zig-served UI.
    const serve_step = b.step("serve", "Launch the full docker stack (incl. the :5173 dashboard) and open the Soulseek port");
    serve_step.dependOn(&compose_up.step);
    serve_step.dependOn(&upnp.step);
    serve_step.dependOn(&announce.step);

    // Kept as an optional standalone bundle build (e.g. for a custom static host); not part of
    // `serve`, which uses the docker `frontend` container.
    const ui_step = b.step("ui", "Build the frontend bundle (bakes VITE_API_KEY from .env)");
    ui_step.dependOn(&build_ui.step);

    const up_step = b.step("up", "Start the full docker stack (db, redis, jaeger, slsk, api, frontend)");
    up_step.dependOn(&compose_up.step);
    up_step.dependOn(&announce.step);

    const forward_step = b.step("forward", "Open the Soulseek listen port on your router via UPnP");
    forward_step.dependOn(&upnp.step);

    // `zig build sync -Dplaylist=<url-or-id>` starts a Spotify sync via the running API.
    const sync = b.addSystemCommand(&.{ "bash", "tools/sync.sh" });
    sync.addArg(sync_playlist);
    sync.addArg(b.fmt("{d}", .{sync_workers}));
    sync.addArg(b.fmt("{d}", .{sync_chunk}));
    const sync_step = b.step("sync", "Start a Spotify sync: zig build sync -Dplaylist=<url-or-id> [-Dworkers=N -Dchunk=N]");
    sync_step.dependOn(&sync.step);

    const compose_down = b.addSystemCommand(&.{
        "docker", "compose", "--project-directory", boot_dir, "-f", boot_compose, "down",
    });
    const down_step = b.step("down", "Stop the backend services");
    down_step.dependOn(&compose_down.step);
}
