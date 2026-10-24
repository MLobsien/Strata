# The Strata desktop app: a Tauri (Rust) shell that embeds a Node "app host" (apps/host) plus the
# staged Control (the terminal's Python bundle), the pinned standalone Node, and the DeepSeek
# Harness.
#
# Pieces (see also apps/desktop/README and packaging/README):
#   apps/host          vite/react UI + a Node server (server/index.mjs); built here by vite.
#   apps/desktop       the Tauri wrapper: src-tauri/Cargo.toml builds the native shell;
#                      tauri.conf.json declares bundle resources (host/dist, host/server,
#                      node binary, control/, harness/, engine-bundle/).
#   resources/node     pinned standalone Node 24.12.0 (digests in apps/desktop/scripts/fetch-node.sh).
#   resources/control  the terminal python bundle (apps/desktop/scripts/stage-control.py).
#   resources/harness  the pinned DeepSeek Harness deploy (apps/desktop/scripts/stage-harness.mjs).
#   engine-bundle      an engine component for the platform (nix/engines/*.nix outputs).
#
# Honest status until the first real build fills the two hashes: the node UI and the resources
# build (npmDepsHash), and the rust shell does not (cargoHash empty means the cargoDeps attr and
# the shell-binary copy are simply absent, which strays green in eval but yields an app package
# without a shell binary). Fill both in on a GUI-capable box and remove this note.
{
  version ? "0.2.3",
  lib,
  stdenv,
  pkg-config,
  wrapGAppsHook3,
  cargo,
  rustc,
  rustPlatform,
  nodejs,
  fetchNpmDeps,
  makeWrapper,
  webkitgtk_4_1,
  gtk3,
  glib-networking,
  cargoHash ? "",
  npmDepsHash ? "",
  bundled-node ? null,
  bundled-control ? null,
  bundled-harness ? null,
  bundled-engine ? null,
  ...
}: let
  # The built host UI exists only when npmDepsHash was provided (fetchNpmDeps demands a real hash
  # and a "" one produces an empty store path at eval); with it unset, null keeps the reference
  # out of the derivation entirely and preConfigure falls back to copying the source tree.
  host = stdenv.mkDerivation {
    pname = "strata-host-ui";
    inherit version;
    src = ./..;
    sourceRoot = "source/apps/host";

    nativeBuildInputs = [nodejs];
    npmDeps = fetchNpmDeps {
      src = ./..;
      sha256 = lib.fakeSha256;
      sourceRoot = "apps";
    };

    buildPhase = ''
      runHook preBuild
      npm run build
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out/dist $out/server
      cp -r dist/* $out/dist/
      cp -r server/* $out/server/
      cp package.json $out/
      runHook postInstall
    '';
  };

  appAttrs = {
    name = "strata-app";
    inherit version;
    src = ./..;

    preConfigure = ''
      mkdir -p host
      cp -r ${host}/dist host/dist
      cp -r ${host}/server host/server
      cp ${host}/package.json host/package.json
      }
    '';

    nativeBuildInputs =
      [makeWrapper cargo rustc rustPlatform.cargoSetupHook]
      ++ lib.optionals stdenv.hostPlatform.isLinux
      [pkg-config wrapGAppsHook3];
    buildInputs =
      lib.optionals stdenv.hostPlatform.isLinux
      [webkitgtk_4_1 gtk3 glib-networking];

    installPhase = let
      copyRes = name: src:
        lib.optionalString (src != null) "cp -r ${src} $out/resources/${name}";
    in ''
      runHook preInstall
      mkdir -p $out/bin $out/resources

      cp target/release/strata-desktop $out/bin/strata-app

      ${copyRes "node" bundled-node}
      ${copyRes "control" bundled-control}
      ${copyRes "harness" bundled-harness}
      ${copyRes "engine-bundle" bundled-engine}
      runHook postInstall
    '';

    meta = with lib; {
      description = "Strata Desktop (the GUI app: Tauri shell + node host + staged control/harness)";
      license = licenses.mit;
      maintainers = [];
      platforms = with platforms; linux ++ darwin;
    };
  };

  cargoAttrs = lib.optionalAttrs (cargoHash != "") {
    cargoDeps = rustPlatform.fetchCargoVendor {
      cargoRoot = "apps/desktop/src-tauri";
      hash = cargoHash;
    };
  };
in
  stdenv.mkDerivation (appAttrs // cargoAttrs)
