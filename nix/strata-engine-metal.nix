# The Apple Silicon (Metal) engine: metal/CMakeLists.txt as a nix derivation, aarch64-darwin only.
#
# What the build needs (metal/CMakeLists.txt):
#   * Apple frameworks (Metal, Foundation, QuartzCore) and the clang of a darwin stdenv:
#     nix trunk on macOS provides these from the SDK ('nixpkgs.aarch64-darwin.stdenv').
#   * metal-cpp: Apple's C++_26 headers, fetched as a zip, pinned by SHA-256
#     (METAL_CPP_URL / METAL_CPP_SHA256 in metal/setup_mac.py). The `metal-cpp` argument takes a
#     fetched-and-unpacked copy; a fetchzip with those values is provided below as `metalCpp`.
#   * a llama.cpp checkout at the pin (STRATA_GGML_DIR; ggml-cpu for the native-expert arithmetic).
#   * the repo's third_party/ggml headers tree (GGML_COMMON / include path) comes with the source.
#
# The project builds only the kernel-tree (mtl_rt) and the engine (strata) when METAL_CPP_DIR is
# set; the runtime_hello test target it also produces is not installed.
#
# NOT BUILT HERE/CHECKED BY A REAL MAC YET: this file was written on a Linux box; `nix build`
# on an actual aarch64-darwin host is what proves it, and the casting says so in meta.
{
  lib,
  stdenv,
  cmake,
  ninja,
  makeWrapper,
  fetchzip,
  llama-cpp,
  zlib,
  # Apple's metal-cpp headers folder (Metal/Metal.hpp inside). Default: the pinned 2026 zip.
  metal-cpp ? import ./metal-cpp.nix {inherit fetchzip;},
  ...
}:
  # metal/CMakeLists.txt FATAL_ERRORs on any non-Apple platform; refuse at eval, on Linux,
  # rather than let someone waste a daemon build on a configured failure.
  assert !stdenv.hostPlatform.isDarwin -> throw "strata-engine-metal: macOS only (metal/CMakeLists.txt refuses a non-Apple platform; skip it with nixpkgs for aarch64-darwin)";
  stdenv.mkDerivation {
    name = "strata-engine-metal";

    src = ../.;

    configureScript = "../metal";    # the Metal project is its own CMake project under metal/
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DMETAL_CPP_DIR=${metal-cpp}"
      "-DSTRATA_GGML_DIR=${llama-cpp.src}"
      "-DSTRATA_METAL_ENGINE=ON"
    ];

    # The Apple frameworks (Metal, Foundation, QuartzCore) come from the SDK inside the darwin
    # stdenv; nothing else is linked (the engine links a static ggml from the llama.cpp pin).
    nativeBuildInputs = [cmake ninja makeWrapper];
    buildInputs = [zlib];

    # The engine banner compile-definition hardcodes a version string in metal/CMakeLists.txt;
    # do not fight it: the package records its real source through the component manifest's build_id.
    installPhase = ''
      runHook preInstall
      mkdir -p $out/engine
      cp strata $out/engine/strata
      runHook postInstall
    '';

    postFixup = ''
      # the engine dlopens nothing beyond the Apple frameworks; a plain wrapper suffices
      wrapProgram $out/engine/strata
    '';

    meta = with lib; {
      description = "Strata's Apple Silicon (Metal) engine";
      platforms = platforms.darwin;
      maintainers = [];
      mainProgram = "strata";
    };
  }
