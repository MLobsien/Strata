{
  strata-terminal,
  strata-engine,
  version ? "0.2.3",
  lib,
  stdenvNoCC,
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
  ...
}: let
  host = stdenvNoCC.mkDerivation {
    name = "strata-host-ui";
    inherit version;
    src = ../.;
    sourceRoot = "source/apps/host";

    nativeBuildInputs = [nodejs];
    npmDeps = fetchNpmDeps {
      src = ./../apps/host;
    };

    buildPhase = ''
      npm run build
    '';

    installPhase = ''
      mkdir -p $out/dist $out/server
      cp -r dist/ $out/
      cp -r server/ $out/
      cp package.json $out/
    '';
  };
in
  stdenv.mkDerivation {
    name = "strata-app";
    inherit version;
    src = ./..;

    cargoDeps = rustPlatform.fetchCargoVendor {
      # cargoRoot = "apps/desktop/src-tauri";
      src = ../apps/desktop/src-tauri;
      hash = "sha256-${builtins.concatStringsSep "" (builtins.genList (_: "0") 43)}";
    };

    preConfigure = ''
      mkdir -p host
      cp -r ${host}/dist host/dist
      cp -r ${host}/server host/server
      cp ${host}/package.json host/package.json
    '';

    nativeBuildInputs =
      [makeWrapper cargo rustc rustPlatform.cargoSetupHook]
      ++ lib.optionals stdenv.hostPlatform.isLinux [pkg-config wrapGAppsHook3];

    buildInputs =
      lib.optionals stdenv.hostPlatform.isLinux
      [webkitgtk_4_1 gtk3 glib-networking];

    installPhase = ''
      mkdir -p $out/bin $out/resources/node

      cp target/release/strata-desktop $out/bin/strata-app

      ln -s ${nodejs}/bin/node $out/resources/node/node
      ln -s ${strata-terminal}/${strata-terminal.passthru.sitePackages} $out/resources/control
      ln -s ${strata-engine}/engine $out/engine-bundle
    '';

    meta = with lib; {
      description = "Strata Desktop (the GUI app: Tauri shell + node host + staged control/harness)";
      license = licenses.mit;
      maintainers = [];
      platforms = with platforms; linux ++ darwin;
    };
  }
