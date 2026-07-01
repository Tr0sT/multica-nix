{ self }:

{
  name = "multica";

  nodes.machine = { pkgs, ... }: {
    imports = [ self.nixosModules.multica ];

    environment.systemPackages = [
      pkgs.curl
      pkgs.nettools
    ];

    services.multica = {
      enable = true;
      environmentFile = "/var/lib/multica/multica.env";
    };

    systemd.tmpfiles.rules = [
      "f /var/lib/multica/multica.env 0600 multica multica - JWT_SECRET=vm-test-jwt-secret-change-me"
    ];
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("postgresql.service")
    machine.wait_until_succeeds("test $(systemctl show -p Result --value multica-db-setup.service) = success && test $(systemctl show -p InactiveEnterTimestampMonotonic --value multica-db-setup.service) != 0")
    machine.wait_until_succeeds("test $(systemctl show -p Result --value multica-migrate.service) = success && test $(systemctl show -p InactiveEnterTimestampMonotonic --value multica-migrate.service) != 0")
    machine.wait_for_unit("multica-backend.service")
    machine.wait_for_unit("multica-web.service")
    machine.wait_for_open_port(8080)
    machine.wait_for_open_port(3000)
    machine.succeed("curl -fsS http://127.0.0.1:8080/health")
    machine.succeed("curl -fsS http://127.0.0.1:8080/readyz")
    machine.succeed("curl -fsS http://127.0.0.1:3000/")
    machine.succeed("test $(stat -c '%U:%G' /var/lib/multica/uploads) = multica:multica")
  '';
}
