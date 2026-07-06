# Migrating from Docker Compose to native NixOS Multica

This repo packages Multica natively for Nix/NixOS. Migrate in two phases: side-by-side test on ports `13000/18080`, then a planned downtime production cutover.

## Hard warnings

- Do not run `docker compose down -v`.
- Do not `docker volume rm multica_pgdata` or remove any Multica Docker volumes.
- Do not point native Multica at the live Docker database.
- Keep Docker volumes until native deployment has been running successfully for a while.
- `import-to-native.sh` replaces the target native database only when `--replace-existing-db` is passed; double-check `--db` before running it.

## Side-by-side test

1. Export Docker data:

   ```bash
   cd ~/.multica/server
   /path/to/multica-nix/scripts/export-from-docker.sh
   ```

   The export directory is created with mode `0700` because it contains a database dump, upload data, and sanitized environment material.

2. Sanitize the old Docker `.env`:

   ```bash
   /path/to/multica-nix/scripts/sanitize-docker-env.sh --output ./backups/<timestamp>/env.sanitized.example .env
   install -m 0600 ./backups/<timestamp>/env.sanitized.example /var/lib/multica/multica.env
   ```

3. Enable native Multica beside Docker on ports `13000/18080`; see `examples/test-next-to-docker.nix`.

4. Apply the NixOS configuration, then import into the test database:

   ```bash
   /path/to/multica-nix/scripts/import-to-native.sh \
     --replace-existing-db \
     --db multica_nix_test \
     --backup-dir ./backups/<timestamp> \
     --backend-port 18080 \
     --frontend-port 13000
   ```

5. Verify login, workspaces, issues, comments, attachments, and daemon connectivity.

## Production cutover

```bash
# In old Multica checkout
docker compose -f docker-compose.selfhost.yml stop frontend backend

# Final export while writes are stopped
/path/to/multica-nix/scripts/export-from-docker.sh

# Import final backup into native DB
/path/to/multica-nix/scripts/import-to-native.sh --replace-existing-db --db multica --backup-dir ./backups/<timestamp>

# Stop Docker but DO NOT delete volumes
docker compose -f docker-compose.selfhost.yml down

# Switch NixOS ports to 3000/8080 or enable reverse proxy config
nixos-rebuild switch
```

If anything looks wrong, stop native services and restart Docker frontend/backend without deleting volumes.
