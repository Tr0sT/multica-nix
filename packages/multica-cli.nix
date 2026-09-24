{
  fetchurl,
  lib,
  stdenvNoCC,
  version ? "0.5.3",
}:

let
  sources = {
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-TtIizIKdiawxijcH3zT2dUsI3wI1eTkDbQpbq15JTZI=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-ktZ7l+Qesm6zg3N7yFSLKYID/D7ZtH6FEkJTI98ZsiU=";
    };
  };
  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "multica-cli does not support ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "multica-cli";
  inherit version;

  src = fetchurl {
    url = "https://github.com/multica-ai/multica/releases/download/v${version}/multica-cli-${version}-linux-${source.arch}.tar.gz";
    inherit (source) hash;
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    install -Dm755 multica $out/bin/multica
    install -Dm644 LICENSE $out/share/licenses/multica/LICENSE

    runHook postInstall
  '';

  passthru = { inherit version; };
  meta = {
    description = "CLI and local runtime daemon for Multica";
    homepage = "https://github.com/multica-ai/multica";
    mainProgram = "multica";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
