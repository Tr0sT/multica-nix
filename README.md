# multica-nix

Experimental external native Nix/NixOS packaging for [Multica](https://github.com/multica-ai/multica). It packages the CLI/runtime daemon, Go backend, Next.js web frontend, a NixOS module, and a VM test.

This flake tracks upstream Multica releases through an automated update workflow. The currently pinned version lives in `flake.nix` and the package derivations.

## Flake input

```nix
{
  inputs.multica-nix.url = "github:Tr0sT/multica-nix";
  inputs.multica-nix.inputs.nixpkgs.follows = "nixpkgs";
}
```

## Binary cache (Cachix)

GitHub Actions builds the Multica packages and publishes their Nix store paths to the public [`nuclearband`](https://app.cachix.org/cache/nuclearband) Cachix binary cache. Configure it on NixOS machines to download prebuilt packages instead of compiling them locally:

```nix
{
  nix.settings.substituters = [
    "https://nuclearband.cachix.org"
  ];

  nix.settings.trusted-public-keys = [
    "nuclearband.cachix.org-1:SXOkxUWakTie6D8xHjpTTibQlgH4M+Z3f+S5n2GlxhE="
  ];
}
```

After rebuilding the system with this configuration, commands such as:

```bash
sudo nixos-rebuild switch --flake github:Tr0sT/multica-nix
```

will use cached Multica builds whenever a matching store path is available.

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

## CLI and runtime daemon only

Machines that only execute agent tasks can install the CLI without enabling the Multica backend or web frontend:

```nix
{
  environment.systemPackages = [
    inputs.multica-nix.packages.${pkgs.stdenv.hostPlatform.system}.multica-cli
  ];
}
```

Run `multica login` once, then manage `multica daemon start --foreground` with a user or system service. Keep CLI self-updates disabled when the binary comes from Nix; update the flake input and rebuild instead.

## Public URLs and reverse proxies

For a public or cross-machine deployment, keep the raw backend private and put Multica behind a reverse proxy or tunnel. Set the public frontend URL, and set `backend.publicUrl` only when the backend/API is reachable at a distinct public URL:

```nix
{
  services.multica = {
    frontend.publicUrl = "https://multica.example.com";

    backend = {
      # Used as MULTICA_PUBLIC_URL for absolute webhook URLs.
      publicUrl = "https://multica-api.example.com";

      # Example for a same-host reverse proxy. Add only proxies you control.
      trustedProxies = [ "127.0.0.1/32" ];
    };
  };
}
```

`services.multica.openFirewall = true` opens the frontend port only. The backend port is controlled separately by `services.multica.backend.openFirewall`; avoid enabling it unless another firewall layer keeps the raw API private.

## Updating Multica

Automated updates are handled by `.github/workflows/update.yml`. The workflow checks the latest `multica-ai/multica` release every six hours and can also be run manually from the Actions tab with an explicit version.

The update script can be run locally too:

```bash
nix develop -c bash scripts/update.sh --latest
nix develop -c bash scripts/update.sh --version <version>
```

It updates:

- `version` in `flake.nix`
- default package versions
- CLI release hashes for Linux AMD64 and ARM64
- upstream source hashes
- Go `vendorHash`
- pnpm dependency hash

Manual update checklist:

```bash
nix flake show
nix build .#multica-cli
nix build .#multica-server
nix build .#multica-web
nix build .#checks.x86_64-linux.multica-vm
nix flake check
```

## Troubleshooting

- Frontend API routing is compiled into the Next.js build via `services.multica.web.remoteApiUrl` / `REMOTE_API_URL`; rebuild if it changes.
- Set `services.multica.web.nextPublicWsUrl` when clients need an explicit WebSocket URL.
- `FRONTEND_ORIGIN`, `CORS_ALLOWED_ORIGINS`, `GOOGLE_REDIRECT_URI`, and `MULTICA_APP_URL` are generated from `frontend.publicUrl` by the module.
- `services.multica.backend.publicUrl` is exported as `MULTICA_PUBLIC_URL`; set it when webhook URLs must use a distinct public API origin.
- `services.multica.backend.trustedProxies` is exported as `MULTICA_TRUSTED_PROXIES`; set it only to CIDRs for reverse proxies you control.
- Local PostgreSQL uses PostgreSQL 17 and enables the `vector` extension with `multica-db-setup.service`.
- Local uploads live at `services.multica.storage.localUploadDir` (default `/var/lib/multica/uploads`).
- Logs:

  ```bash
  journalctl -u multica-backend -f
  journalctl -u multica-web -f
  journalctl -u multica-migrate -b
  ```

## Known limitations

The backend currently only honors `PORT` and binds to `:${PORT}`; the module keeps `backend.listenAddress` for UX/documentation, but runtime binding is controlled upstream. Keep `services.multica.backend.openFirewall = false` unless you intentionally expose or separately firewall the raw backend port.
