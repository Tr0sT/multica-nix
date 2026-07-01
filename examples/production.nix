{
  inputs,
  ...
}:

{
  imports = [ inputs.multica-nix.nixosModules.multica ];

  services.multica = {
    enable = true;
    environmentFile = "/var/lib/multica/multica.env";
    frontend.publicUrl = "https://multica.example.com";
    web.remoteApiUrl = "http://127.0.0.1:8080";
  };
}
