{
  version ? "",
  metal-cpp ? import ../metal-cpp.nix {},
  lib,
  stdenv,
  cmake,
  ninja,
  makeWrapper,
  fetchzip,
  llama-cpp,
  zlib,
  ...
}:
stdenv.mkDerivation {
  name = "strata-engine-metal";
  src = ../..;
  inherit version;

  # The Metal project sits under metal/ as its own CMake project (sibling of sycl/ and the top level).
  configureScript = "../metal";
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DMETAL_CPP_DIR=${metal-cpp}/metal-cpp_26"
    "-DSTRATA_GGML_DIR=${llama-cpp.src}"
    "-DSTRATA_METAL_ENGINE=ON"
  ];

  # The Apple frameworks (Metal, Foundation, QuartzCore) come from the SDK inside the darwin stdenv;
  # the engine links a static ggml from the llama.cpp pin and nothing else beyond zlib.
  nativeBuildInputs = [cmake ninja makeWrapper];
  buildInputs = [zlib];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/engine
    cp strata $out/engine/strata
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
