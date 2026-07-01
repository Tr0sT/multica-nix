{
  inputs,
  ...
}:

{
  imports = [ inputs.multica-nix.nixosModules.multica ];

  services.multica = {
    enable = true;

    frontend = {
      listenAddress = "127.0.0.1";
      port = 13000;
      publicUrl = "http://127.0.0.1:13000";
    };

    backend = {
      listenAddress = "127.0.0.1";
      port = 18080;
    };

    web = {
      remoteApiUrl = "http://127.0.0.1:18080";
      nextPublicWsUrl = "ws://127.0.0.1:18080/ws";
    };

    database = {
      createLocally = true;
      name = "multica_nix_test";
      user = "multica";
    };

    environmentFile = "/var/lib/multica/multica.env";
  };
}
