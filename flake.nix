{
  description = "Native Nix/NixOS packaging for Multica";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
      version = "0.3.40";
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          multica-server = pkgs.callPackage ./packages/multica-server.nix { inherit version; };
          multica-web = pkgs.callPackage ./packages/multica-web.nix { inherit version; };
        in
        {
          inherit multica-server multica-web;
          default = multica-server;
        }
      );

      nixosModules.multica = import ./modules/multica.nix { inherit self; };

      checks.x86_64-linux.multica-vm =
        let
          pkgs = pkgsFor "x86_64-linux";
        in
        pkgs.testers.runNixOSTest (import ./tests/multica.nix { inherit self; });

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.git
              pkgs.nixfmt-rfc-style
              pkgs.go_1_26
              pkgs.nodejs_22
              pkgs.pnpm_10
              pkgs.postgresql_17
            ];
          };
        }
      );
    };
}
