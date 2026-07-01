# multica-nix

Experimental external native Nix/NixOS packaging for [Multica](https://github.com/multica-ai/multica). It builds the Go backend, Next.js web frontend, a NixOS module, migration helpers, and a VM test without Docker/OCI containers at runtime.

Packaged Multica version: `0.3.34` (`v0.3.34`).

## Flake input

```nix
{
  inputs.multica-nix.url = "github:Tr0sT/multica-nix";
  inputs.multica-nix.inputs.nixpkgs.follows = "nixpkgs";
}
```

## Minimal NixOS usage

```nix
{
  imports = [ inputs.multica-nix.nixosModules.multica ];

  services.multica = {
    enable = true;
    environmentFile = "/var/lib/multica/multica.env";
  };
}
```

Put secrets and integration credentials in `/var/lib/multica/multica.env`, not in Nix. At minimum set a strong `JWT_SECRET`.

## Test next to Docker

Use `examples/test-next-to-docker.nix` to run native Multica on frontend port `13000` and backend port `18080` while the Docker Compose instance keeps `3000/8080`.

## Migration

See [`docs/migration-from-docker.md`](docs/migration-from-docker.md). Short form:

```bash
cd ~/.multica/server
/path/to/multica-nix/scripts/export-from-docker.sh
/path/to/multica-nix/scripts/sanitize-docker-env.sh --output /var/lib/multica/multica.env .env
/path/to/multica-nix/scripts/import-to-native.sh --db multica_nix_test --backup-dir ./backups/<timestamp> --backend-port 18080 --frontend-port 13000
```

Do not delete Docker volumes during migration.

## Updating Multica

1. Check the latest upstream release tag.
2. Update `version` in `flake.nix`.
3. Update hashes in `packages/multica-server.nix` and `packages/multica-web.nix` by running builds and replacing Nix's reported hashes.
4. Run:

   ```bash
   nix flake show
   nix build .#multica-server
   nix build .#multica-web
   nix build .#checks.x86_64-linux.multica-vm
   nix flake check
   ```

## Troubleshooting

- Frontend API routing is compiled into the Next.js build via `services.multica.web.remoteApiUrl` / `REMOTE_API_URL`; rebuild if it changes.
- Set `services.multica.web.nextPublicWsUrl` when clients need an explicit WebSocket URL.
- `FRONTEND_ORIGIN`, `CORS_ALLOWED_ORIGINS`, and `MULTICA_APP_URL` are generated from `frontend.publicUrl` by the module.
- Local PostgreSQL uses PostgreSQL 17 and enables the `vector` extension with `multica-db-setup.service`.
- Local uploads live at `services.multica.storage.localUploadDir` (default `/var/lib/multica/uploads`).
- Logs:

  ```bash
  journalctl -u multica-backend -f
  journalctl -u multica-web -f
  journalctl -u multica-migrate -b
  ```

## Known limitations

Multica v0.3.34 backend only honors `PORT` and binds to `:${PORT}`; the module keeps `backend.listenAddress` for UX/documentation, but runtime binding is controlled upstream. Keep `openFirewall = false` or put it behind a reverse proxy/firewall for LAN-only deployments.
