#!/usr/bin/env bash
set -euo pipefail

compose_file="docker-compose.selfhost.yml"
project="multica"
postgres_service="postgres"
backend_service="backend"
out=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose-file) compose_file="$2"; shift 2 ;;
    --project-name) project="$2"; shift 2 ;;
    --postgres-service) postgres_service="$2"; shift 2 ;;
    --backend-service) backend_service="$2"; shift 2 ;;
    --output) out="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--compose-file FILE] [--project-name NAME] [--output DIR]"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$compose_file" ]] || { echo "compose file not found: $compose_file" >&2; exit 1; }
if [[ -z "$out" ]]; then out="./backups/$(date -u +%Y%m%dT%H%M%SZ)"; fi
mkdir -p "$out"
compose=(docker compose -p "$project" -f "$compose_file")
postgres_cid="$(${compose[@]} ps -q "$postgres_service")"
backend_cid="$(${compose[@]} ps -q "$backend_service")"
[[ -n "$postgres_cid" ]] || { echo "Postgres service container not found" >&2; exit 1; }
[[ -n "$backend_cid" ]] || { echo "Backend service container not found" >&2; exit 1; }

${compose[@]} exec -T "$postgres_service" sh -lc 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl' > "$out/db.dump"
mount_source="$(docker inspect "$backend_cid" --format '{{range .Mounts}}{{if eq .Destination "/app/data/uploads"}}{{.Source}}{{end}}{{end}}')"
[[ -n "$mount_source" ]] || { echo "Could not find backend mount destination /app/data/uploads" >&2; exit 1; }
tar -C "$mount_source" -czf "$out/uploads.tar.gz" .

${compose[@]} config > "$out/docker-compose.effective.yml"
docker inspect "$postgres_cid" "$backend_cid" --format '{{.Name}} {{.Config.Image}} {{.Image}}' > "$out/docker-images.txt"
${compose[@]} ps > "$out/docker-ps.txt"
docker volume ls > "$out/docker-volumes.txt"
if [[ -f .env ]]; then "$(dirname "$0")/sanitize-docker-env.sh" --output "$out/env.sanitized.example" .env || true; fi
cat > "$out/README.restore-notes.txt" <<EOF
Backup created from compose file: $compose_file
Compose project: $project
Postgres service/container: $postgres_service / $postgres_cid
Backend service/container: $backend_service / $backend_cid
Uploads source: $mount_source

Next steps:
1. Review env.sanitized.example and install it as /var/lib/multica/multica.env.
2. Enable native services.multica on non-conflicting test ports first.
3. Run import-to-native.sh --backup-dir $out --db multica_nix_test.
4. Verify login, workspaces, issues, comments, attachments, and daemon connectivity.
EOF

echo "Export complete: $out"
echo "Next: ./scripts/import-to-native.sh --backup-dir $out --db multica_nix_test"
echo "Do not run docker compose down -v or remove Docker volumes."
