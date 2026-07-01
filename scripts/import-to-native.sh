#!/usr/bin/env bash
set -euo pipefail

db="multica"; db_user="multica"; state_dir="/var/lib/multica"; backup_dir=""; backend_port="8080"; frontend_port="3000"; svc_user="multica"; svc_group="multica"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir) backup_dir="$2"; shift 2 ;;
    --db) db="$2"; shift 2 ;;
    --db-user) db_user="$2"; shift 2 ;;
    --state-dir) state_dir="$2"; shift 2 ;;
    --backend-port) backend_port="$2"; shift 2 ;;
    --frontend-port) frontend_port="$2"; shift 2 ;;
    --user) svc_user="$2"; shift 2 ;;
    --group) svc_group="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 --backup-dir DIR [--db multica] [--db-user multica] [--state-dir /var/lib/multica]"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$backup_dir" ]] || { echo "missing --backup-dir" >&2; exit 2; }
[[ -f "$backup_dir/db.dump" && -f "$backup_dir/uploads.tar.gz" ]] || { echo "backup must contain db.dump and uploads.tar.gz" >&2; exit 1; }

systemctl stop multica-web.service multica-backend.service multica-migrate.service || true
sudo -u postgres dropdb --if-exists "$db"
sudo -u postgres createdb -O "$db_user" "$db"
sudo -u postgres psql -d "$db" -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION IF NOT EXISTS vector;'
sudo -u postgres pg_restore --no-owner --role="$db_user" -d "$db" "$backup_dir/db.dump"
install -d -m 0750 -o "$svc_user" -g "$svc_group" "$state_dir/uploads"
tar -xzf "$backup_dir/uploads.tar.gz" -C "$state_dir/uploads"
chown -R "$svc_user:$svc_group" "$state_dir/uploads"
systemctl start multica-migrate.service
systemctl start multica-backend.service
systemctl start multica-web.service
curl -fsS "http://127.0.0.1:${backend_port}/health"
curl -fsS "http://127.0.0.1:${backend_port}/readyz"
curl -fsS "http://127.0.0.1:${frontend_port}/"
echo "Native Multica restore verified."
