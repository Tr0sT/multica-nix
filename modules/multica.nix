{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    optional
    optionalAttrs
    optionalString
    unique
    types
    ;
  cfg = config.services.multica;
  serverPackage = cfg.package.server;
  rawWebPackage = cfg.package.web;
  webPackage =
    if rawWebPackage ? override then
      rawWebPackage.override {
        remoteApiUrl = cfg.web.remoteApiUrl;
        nextPublicWsUrl = cfg.web.nextPublicWsUrl;
        appVersion = serverPackage.passthru.version or serverPackage.version or "dev";
      }
    else
      rawWebPackage;
  dbUrl =
    if cfg.database.createLocally then
      "postgres://${cfg.database.user}@/${cfg.database.name}?host=/run/postgresql&sslmode=disable"
    else
      cfg.database.url;
  dbSetupScript = pkgs.writeShellScript "multica-db-setup" ''
    set -euo pipefail

    ${pkgs.postgresql_17}/bin/psql -d postgres -v ON_ERROR_STOP=1 <<'SQL'
    ALTER DATABASE "${cfg.database.name}" OWNER TO "${cfg.database.user}";
    SQL

    ${pkgs.postgresql_17}/bin/psql -d "${cfg.database.name}" -v ON_ERROR_STOP=1 <<'SQL'
    CREATE EXTENSION IF NOT EXISTS vector;
    ALTER SCHEMA public OWNER TO "${cfg.database.user}";
    GRANT USAGE, CREATE ON SCHEMA public TO "${cfg.database.user}";
    GRANT ALL PRIVILEGES ON DATABASE "${cfg.database.name}" TO "${cfg.database.user}";
    SQL
  '';
in
{
  options.services.multica = {
    enable = mkEnableOption "Multica";

    user = mkOption {
      type = types.str;
      default = "multica";
      description = "User that runs Multica services.";
    };
    group = mkOption {
      type = types.str;
      default = "multica";
      description = "Group that runs Multica services.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/multica";
      description = "Writable Multica state directory.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Runtime path to env file with secrets only. Must not be a Nix store path.";
    };

    package = {
      server = mkOption {
        type = types.package;
        default = self.packages.${pkgs.system}.multica-server;
        description = "Multica backend package.";
      };
      web = mkOption {
        type = types.package;
        default = self.packages.${pkgs.system}.multica-web;
        description = "Multica web package.";
      };
    };

    database = {
      createLocally = mkOption {
        type = types.bool;
        default = true;
        description = "Create and manage a local PostgreSQL 17 database.";
      };
      name = mkOption {
        type = types.str;
        default = "multica";
        description = "PostgreSQL database name.";
      };
      user = mkOption {
        type = types.str;
        default = "multica";
        description = "PostgreSQL database user.";
      };
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "External DATABASE_URL when createLocally is false.";
      };
    };

    backend = {
      listenAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Requested backend listen address. Multica v0.3.34 only honors PORT and binds all interfaces.";
      };
      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Backend HTTP port.";
      };
      publicUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Public backend URL if distinct from frontend.";
      };
      metricsAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional METRICS_ADDR listener, for example 127.0.0.1:9090.";
      };
    };

    frontend = {
      listenAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Frontend listen address.";
      };
      port = mkOption {
        type = types.port;
        default = 3000;
        description = "Frontend HTTP port.";
      };
      publicUrl = mkOption {
        type = types.str;
        default = "http://localhost:3000";
        description = "Public frontend URL.";
      };
    };

    web = {
      remoteApiUrl = mkOption {
        type = types.str;
        default = "http://127.0.0.1:${toString cfg.backend.port}";
        description = "Build-time REMOTE_API_URL used by the Next.js frontend.";
      };
      nextPublicWsUrl = mkOption {
        type = types.str;
        default = "";
        description = "Build-time NEXT_PUBLIC_WS_URL. Useful when not using a reverse proxy.";
      };
    };

    storage = {
      localUploadDir = mkOption {
        type = types.str;
        default = "${cfg.stateDir}/uploads";
        description = "Absolute local upload directory.";
      };
      localUploadBaseUrl = mkOption {
        type = types.str;
        default = cfg.frontend.publicUrl;
        description = "Base URL for local upload links.";
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall ports for frontend and backend.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.environmentFile == null || !(lib.hasPrefix builtins.storeDir cfg.environmentFile);
        message = "services.multica.environmentFile must be a runtime path, not a Nix store path.";
      }
      {
        assertion = cfg.database.createLocally || cfg.database.url != null;
        message = "services.multica.database.url is required when database.createLocally = false.";
      }
      {
        assertion = !cfg.database.createLocally || cfg.database.user == cfg.user;
        message = "For local peer-auth PostgreSQL, services.multica.database.user must match services.multica.user.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.storage.localUploadDir;
        message = "services.multica.storage.localUploadDir must be absolute.";
      }
    ];

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      createHome = true;
    };

    services.postgresql = mkIf cfg.database.createLocally {
      enable = true;
      package = pkgs.postgresql_17;
      extensions = ps: [ ps.pgvector ];
      ensureDatabases = unique [
        cfg.database.name
        cfg.database.user
      ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensureDBOwnership = true;
        }
      ];
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [
      cfg.frontend.port
      cfg.backend.port
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.storage.localUploadDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.multica-db-setup = mkIf cfg.database.createLocally {
      description = "Prepare Multica PostgreSQL database";
      after = [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      requires = [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        ExecStart = dbSetupScript;
      };
    };

    systemd.services.multica-migrate = {
      description = "Run Multica database migrations";
      after = optional cfg.database.createLocally "multica-db-setup.service";
      requires = optional cfg.database.createLocally "multica-db-setup.service";
      before = [ "multica-backend.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        DATABASE_URL = dbUrl;
      };
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${serverPackage}/share/multica";
        ExecStart = "${serverPackage}/bin/multica-migrate up";
        EnvironmentFile = optional (cfg.environmentFile != null) cfg.environmentFile;
      };
    };

    systemd.services.multica-backend = {
      description = "Multica backend";
      after = [
        "network.target"
        "multica-migrate.service"
      ];
      requires = [ "multica-migrate.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        DATABASE_URL = dbUrl;
        PORT = toString cfg.backend.port;
        APP_ENV = "production";
        FRONTEND_ORIGIN = cfg.frontend.publicUrl;
        CORS_ALLOWED_ORIGINS = cfg.frontend.publicUrl;
        MULTICA_APP_URL = cfg.frontend.publicUrl;
        LOCAL_UPLOAD_DIR = cfg.storage.localUploadDir;
        LOCAL_UPLOAD_BASE_URL = cfg.storage.localUploadBaseUrl;
      }
      // optionalAttrs (cfg.backend.metricsAddress != null) {
        METRICS_ADDR = cfg.backend.metricsAddress;
      };
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = lib.removePrefix "/var/lib/" cfg.stateDir;
        WorkingDirectory = "${serverPackage}/share/multica";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${cfg.storage.localUploadDir}";
        ExecStart = "${serverPackage}/bin/multica-server";
        Restart = "on-failure";
        EnvironmentFile = optional (cfg.environmentFile != null) cfg.environmentFile;
      };
    };

    systemd.services.multica-web = {
      description = "Multica web frontend";
      after = [
        "network.target"
        "multica-backend.service"
      ];
      wants = [ "multica-backend.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        NODE_ENV = "production";
        HOSTNAME = cfg.frontend.listenAddress;
        PORT = toString cfg.frontend.port;
      };
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${webPackage}/bin/multica-web";
        Restart = "on-failure";
      };
    };
  };
}
