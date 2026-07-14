{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  makeWrapper,
  nodejs_22,
  pnpm_10,
  pnpmConfigHook,
  version ? "0.4.1",
  remoteApiUrl ? "http://127.0.0.1:8080",
  nextPublicWsUrl ? "",
  appVersion ? version,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "multica-web";
  inherit version;

  src = fetchFromGitHub {
    owner = "multica-ai";
    repo = "multica";
    rev = "v${finalAttrs.version}";
    hash = "sha256-epJhYCDFfRXU8Uzx/JowQbOESqOFoK0cLaILxIxBANI=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 4;
    pnpmWorkspaces = [ "@multica/web..." ];
    hash = "sha256-bpj3YgbRq57JG27HU3uLsI1UF/NLrj7BQZ/eyId3Arw=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs_22
    pnpm_10
    pnpmConfigHook
  ];

  postPatch = ''
    node <<'JS'
    const fs = require("fs");
    function replace(path, from, to) {
      let text = fs.readFileSync(path, "utf8");
      if (!text.includes(from)) throw new Error(`missing pattern in ''${path}: ''${from}`);
      fs.writeFileSync(path, text.replace(from, to));
    }
    replace("apps/web/app/layout.tsx", 'import { Inter, Geist_Mono, Source_Serif_4 } from "next/font/google";', "");
    replace("apps/web/app/layout.tsx", `const inter = Inter({
      subsets: ["latin"],
      variable: "--font-inter",
    });`, 'const inter = { variable: "" };');
    replace("apps/web/app/layout.tsx", `const geistMono = Geist_Mono({
      subsets: ["latin"],
      variable: "--font-mono",
      fallback: ["ui-monospace", "SFMono-Regular", "Menlo", "Consolas", "monospace"],
    });`, 'const geistMono = { variable: "" };');
    replace("apps/web/app/layout.tsx", `const sourceSerif = Source_Serif_4({
      subsets: ["latin"],
      style: ["normal", "italic"],
      variable: "--font-serif",
      fallback: [
        "ui-serif",
        "Iowan Old Style",
        "Apple Garamond",
        "Baskerville",
        "Times New Roman",
        "serif",
      ],
    });`, 'const sourceSerif = { variable: "" };');
    replace("apps/web/app/(landing)/layout.tsx", 'import { Instrument_Serif, Noto_Serif_SC } from "next/font/google";', "");
    replace("apps/web/app/(landing)/layout.tsx", `const instrumentSerif = Instrument_Serif({
      subsets: ["latin"],
      weight: "400",
      variable: "--font-serif",
    });`, 'const instrumentSerif = { variable: "" };');
    replace("apps/web/app/(landing)/layout.tsx", `const notoSerifSC = Noto_Serif_SC({
      subsets: ["latin"],
      weight: "400",
      variable: "--font-serif-zh",
    });`, 'const notoSerifSC = { variable: "" };');
    JS
  '';

  pnpmInstallFlags = [ "--filter=@multica/web..." ];

  env = {
    REMOTE_API_URL = remoteApiUrl;
    NEXT_PUBLIC_WS_URL = nextPublicWsUrl;
    NEXT_PUBLIC_APP_VERSION = appVersion;
    STANDALONE = "true";
    NODE_ENV = "production";
    NEXT_TELEMETRY_DISABLED = "1";
  };

  buildPhase = ''
    runHook preBuild
    pnpm --filter @multica/web build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -d "$out/share/multica-web"
    cp -R apps/web/.next/standalone/* "$out/share/multica-web/"
    install -d "$out/share/multica-web/apps/web/.next"
    cp -R apps/web/.next/static "$out/share/multica-web/apps/web/.next/static"
    cp -R apps/web/public "$out/share/multica-web/apps/web/public"
    makeWrapper ${lib.getExe nodejs_22} "$out/bin/multica-web"       --chdir "$out/share/multica-web"       --set-default NODE_ENV production       --set-default HOSTNAME 127.0.0.1       --set-default PORT 3000       --add-flags "$out/share/multica-web/apps/web/server.js"
    runHook postInstall
  '';

  passthru = {
    inherit
      version
      remoteApiUrl
      nextPublicWsUrl
      appVersion
      ;
  };
  meta = {
    description = "Multica Next.js web frontend";
    homepage = "https://github.com/multica-ai/multica";
    # Upstream ships a modified Apache-2.0-style source license; keep builds
    # evaluable by default and point operators at upstream for full terms.
    license = lib.licenses.asl20;
    mainProgram = "multica-web";
    platforms = lib.platforms.linux;
  };
})
