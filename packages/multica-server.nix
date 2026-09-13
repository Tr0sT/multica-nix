{
  lib,
  buildGoModule,
  fetchFromGitHub,
  version ? "0.4.43",
}:

buildGoModule rec {
  pname = "multica-server";
  inherit version;

  src = fetchFromGitHub {
    owner = "multica-ai";
    repo = "multica";
    rev = "v${version}";
    hash = "sha256-M/Zc9Bc/IKK2Dwc9TbNGz3OCDmQQOXRTLPYw9iLZs=";
  };

  modRoot = "server";
  vendorHash = "sha256-a3khoppmpS5o+ZJqWjcFwLKpUSXfTG9P5/4lLdBr+tY=";

  # Upstream can raise the required patch release before nixpkgs catches up.
  # Keep the released minimum (1.26.0), not the language version (1.26):
  # Go orders 1.26 < 1.26.0, and dependencies requiring 1.26.0 otherwise make
  # `go mod vendor` fail with "updates to go.mod needed".
  postPatch = ''
    sed -i -E 's/^go 1\.26\.[0-9]+$/go 1.26.0/' server/go.mod
  '';

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
