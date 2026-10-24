{
  version ? "",
  withVision ? true,
  fetchurl,
  lib,
  stdenv,
  cmake,
  ninja,
  makeWrapper,
  llama-cpp,
  zlib,
  ...
}: let
  metal-cpp = fetchurl {
    url = "https://developer.apple.com/metal/cpp/files/metal-cpp_26.zip";
    sha256 = "sha256-TfPAeLmq3LUWIS6csDAEy8XOmj6cBo+jFE0CHbWFo6Q="; # 4df3c078b9aadcb516212e9cb03004cbc5ce9a3e9c068fa3144d021db585a3a4
  };
in
  stdenv.mkDerivation {
    name = "strata-engine-metal";
    src = ../..;
    inherit version;

    configureScript = "$src/metal";   # absolute: the metal/ subproject of this source checkout
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DMETAL_CPP_DIR=${metal-cpp}/metal-cpp_26"
      "-DSTRATA_GGML_DIR=${llama-cpp.src}"
      "-DSTRATA_METAL_ENGINE=ON"
    ];

    nativeBuildInputs = [cmake ninja makeWrapper];
    buildInputs = [zlib];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/engine
      cp strata $out/engine/strata

      ${
      lib.optionalString withVision ''
        # the Mac picture reader (strata-vision), from tools/vision in this checkout; macOS only,
        # so the withVision gate here never fires on a Linux evaluation path
        cmake -S $src/tools/vision -B build-vision -G Ninja \
          ${lib.concatStringsSep " " ((import ./vision-flags.nix {inherit lib;}).flags {
            backend = "metal";
            cuda = null;
            hipcc = null;
            intel-llvm = null;
            llama-cpp = llama-cpp;
          })}
        cmake --build build-vision --target strata-vision -j
        cp build-vision/strata-vision $out/engine/strata-vision
      ''
      }

      runHook postInstall
    '';

    postFixup = ''
      # the engine dlopens nothing beyond Apple's own frameworks; a plain wrapper suffices
      wrapProgram $out/engine/strata
    '';

    meta = {
      description = "Strata's Apple Silicon (Metal) engine";
      license = lib.licenses.mit;
      maintainers = [];
      mainProgram = "strata";
      platforms = lib.platforms.darwin;
      # Written on a Linux host: eval-checked only. A real aarch64-darwin build is what verifies it.
      untested-on-macos-26 = true;
    };
  }
