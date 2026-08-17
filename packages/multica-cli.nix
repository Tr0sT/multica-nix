{
  fetchurl,
  lib,
  stdenvNoCC,
  version ? "0.4.28",
}:

let
  sources = {
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-bu7IytjqqDy7AIYPt+a66JgKw7e6sovgCKmRhi6R0y4=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-WEqgQr40Ar6X4JVY38mn2XLMVPdg6BLN6aOyH+O3rTA=";
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
