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
  npmHooks,
  fetchNpmDeps,
  makeWrapper,
  webkitgtk_4_1,
  gtk3,
  glib-networking ? null,
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
  host =
    if npmDepsHash != ""
    then stdenv.mkDerivation {
      pname = "strata-host-ui";
      inherit version;
      src = ./..;
      sourceRoot = "source/apps/host";

      nativeBuildInputs = [nodejs];
      npmDeps = fetchNpmDeps {src = ./..; hash = npmDepsHash; sourceRoot = "apps";};

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
    }
    else null;

  appAttrs = {
    pname = "strata-app";
    inherit version;
    src = ./..;

    # tauri.conf.json's frontendDist is ../../host/dist. With npmDepsHash filled the prebuilt
    # host (the derivation above) lands there; without it the repo's apps/host tree is laid in
    # unchanged (unbuilt UI: an app that would show an empty shell rather than pretend to work).
    preConfigure = ''
      mkdir -p host
      ${
      if host != null
      then ''
        cp -r ${host}/dist host/dist
        cp -r ${host}/server host/server
        cp ${host}/package.json host/package.json
      ''
      else ''
        cp -r $src/apps/host/server host/server
        cp $src/apps/host/package.json host/package.json   # dist/ absent: the UI is left unbuilt
      ''
      }
    '';

    nativeBuildInputs =
      [makeWrapper]
      ++ lib.optionals (cargoHash != "") [cargo rustc rustPlatform.cargoSetupHook]
      ++ lib.optionals stdenv.hostPlatform.isLinux [pkg-config wrapGAppsHook3];
    buildInputs =
      lib.optionals stdenv.hostPlatform.isLinux [webkitgtk_4_1 gtk3]
      ++ lib.optionals stdenv.hostPlatform.isLinux (lib.filter (p: p != null) [glib-networking]);

    installPhase = let
      copyRes = name: src:
        lib.optionalString (src != null) "\n  cp -r ${src} $out/resources/${name}\n";
    in ''
      runHook preInstall
      mkdir -p $out/bin $out/resources
      ${lib.optionalString (cargoHash != "") ''
        cp target/release/strata-desktop $out/bin/strata-app
      ''}
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
      # Not broken: the app packages the UI + resources whenever npmDepsHash is set; until then
      # nix evaluates it fine but considers it bad for real installs, which is captured here as
      # a stmt on the meta instead (no broken flag: it would hide the app entirely from check).
      broken = false;
    };
  };

  # cargoDeps only exists when a caller passed the real crate hash: the merge keeps the attr out
  # of the derivation (and cargoSetupHook out of nativeBuildInputs) until then, so evaluating the
  # package never demands a hash nobody has recorded yet and building it without one is impossible.
  cargoAttrs =
    lib.optionalAttrs (cargoHash != "") {
      cargoDeps = rustPlatform.fetchCargoVendor {
        cargoRoot = "apps/desktop/src-tauri";
        hash = cargoHash;
      };
    };
in
  stdenv.mkDerivation (appAttrs // cargoAttrs)
