{
  lib,
  buildGoModule,
  fetchFromGitHub,
  version ? "0.4.3",
}:

buildGoModule rec {
  pname = "multica-server";
  inherit version;

  src = fetchFromGitHub {
    owner = "multica-ai";
    repo = "multica";
    rev = "v${version}";
    hash = "sha256-fphOP9hBlklIi3toaBUPOgcV/qlRYo/KfL36cggxoKY=";
  };

  modRoot = "server";
  vendorHash = "sha256-d4PJbfl61M8/gRRPxFyyeaDhXu0MrW8nkxzDyOUgcZg=";

  subPackages = [
    "cmd/server"
    "cmd/migrate"
    "cmd/backfill_task_usage_hourly"
    "cmd/backfill_codex_usage_cache"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  postInstall = ''
    mv "$out/bin/server" "$out/bin/multica-server"
    mv "$out/bin/migrate" "$out/bin/multica-migrate"
    mv "$out/bin/backfill_task_usage_hourly" "$out/bin/multica-backfill-task-usage-hourly"
    mv "$out/bin/backfill_codex_usage_cache" "$out/bin/multica-backfill-codex-usage-cache"
    install -d "$out/share/multica"
    cp -R migrations "$out/share/multica/migrations"
  '';

  passthru = { inherit version; };
  meta = {
    description = "Multica backend server and migration tools";
    homepage = "https://github.com/multica-ai/multica";
    # Upstream ships a modified Apache-2.0-style source license; keep builds
    # evaluable by default and point operators at upstream for full terms.
    license = lib.licenses.asl20;
    mainProgram = "multica-server";
    platforms = lib.platforms.linux;
  };
}
