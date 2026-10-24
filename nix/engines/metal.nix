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

    configureScript = "$src/metal";
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DMETAL_CPP_DIR=${metal-cpp}/metal-cpp_26"
      "-DSTRATA_GGML_DIR=${llama-cpp.src}"
      "-DSTRATA_METAL_ENGINE=ON"
    ];

    nativeBuildInputs = [cmake ninja makeWrapper];
    buildInputs = [zlib];

    # The vision reader compiles after the engine's normal cmake-hook build (postBuild); the
    # default buildPhase stays untouched.
    postBuild =
      lib.optionalString withVision ''
        cmake -S $src/tools/vision -B build-vision -G Ninja \
          -DSTRATA_VISION_METAL=ON -DCMAKE_BUILD_TYPE=Release \
          -DSTRATA_PORTABLE=ON -DLLAMA_DIR=${llama-cpp.src}
        cmake --build build-vision --target strata-vision -j
      '';

    installPhase =
      ''
        runHook preInstall
        mkdir -p $out/engine
        cp strata $out/engine/strata
      ''
      + lib.optionalString withVision ''
        # stage the reader beside the engine; package_engine.py's wanted() picks it up
        cp build-vision/strata-vision $out/engine/strata-vision
      '';

    postFixup = ''
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
