# The AMD (HIP) engine: the top-level CUDA-shaped CMake project built by ROCm's HIP compiler.
#
# From the CMake and packaging scripts:
#   * -DSTRATA_ENABLE_HIP=ON (separate backend from CUDA; both on at once is a configure error)
#   * wave32 AMD cards: gfx1100 / gfx1101 / gfx1102 / gfx1200 / gfx1201 (RDNA3); the gfx906
#     (wave64 compat layer) build is a separate option (STRATA_HIP_GFX906) not covered here
#   * the toolchain is ROCm's (hipcc/amdclang); the prompt path's MMQ needs rocBLAS and
#     hipBLASLt (the CMake probes STRATA_HIPBLASLT_AVAILABLE / STRATA_ROCBLAS_AVAILABLE)
#   * archs: gfx<NNN> strings passed to -DCMAKE_HIP_ARCHITECTURES (the engine default when the
#     variable is unset is the card the build host has). gfx1030 (RX 6000) ships as the rx6000
#     variant in the release feed, not the default package.
#
# NOT BUILT HERE (no AMD card on this machine): eval-only until someone runs
# `nix build .#strata-engine-hip` on an RDNA3 box, like the SYCL package's status.
{
  version ? "",
  withVision ? true,
  arch ? [],
  lib,
  stdenv,
  rocmPackages ? null, # callPackage auto-supplies rocmPackages where available; leave unset elsewhere
  llama-cpp,
  makeWrapper,
  python3,
  uv,
  cmake,
  ninja,
  zlib,
  ...
}: let
  rocmSet = rocmPackages; # callPackage fills it from the calling pkgs' rocmPackages
  # The HIP compiler (hipcc -> clang) nixpkgs' rocmPackages carries; rocBLAS gives the prompt path
  # its GEMMs and hipBLASLt its tuned solution tables.
  hipcc = rocmSet.clr;
  runtime = [rocmSet.clr rocmSet.rocblas rocmSet.hipblaslt];
in
  stdenv.mkDerivation {
    name = "strata-engine-hip";
    src = ../..;
    inherit version;

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DSTRATA_GGML_DIR=${llama-cpp.src}"
      "-DSTRATA_ENABLE_HIP=ON"
      "-DCMAKE_C_COMPILER=${hipcc}/bin/hipcc"
      "-DCMAKE_CXX_COMPILER=${hipcc}/bin/hipcc"
      "-DSTRATA_BUILD_TESTS=OFF"
      "-DCMAKE_HIP_ARCHITECTURES=${lib.concatStringsSep ";" arch}"
    ];

    nativeBuildInputs = [
      makeWrapper
      python3
      uv
      cmake
      ninja
    ];

    buildInputs = [zlib] ++ runtime;

    installPhase = let
      # HIP arch names are already gfx<nnn>: no real/virtual mapping needed (CUDA-only concept)
      archArgs = lib.concatStringsSep " " (map (a: "--arch ${a}") arch);
    in ''
      runHook preInstall
      mkdir -p $out/engine
      cp strata $out/engine/strata
      cp libstrata_kq.so $out/engine/ 2>/dev/null || true

      ${
        lib.optionalString withVision ''
          # the AMD picture reader (strata-vision-hip), arch-matched from tools/vision in this checkout
          cmake -S $src/tools/vision -B build-vision -G Ninja \
            ${lib.concatStringsSep " " [
            "-DCMAKE_BUILD_TYPE=Release"
            "-DSTRATA_PORTABLE=ON"
            "-DLLAMA_DIR=${llama-cpp.src}"
            "-DSTRATA_VISION_HIP=ON"
            "-DCMAKE_C_COMPILER=${hipcc}/bin/hipcc"
            "-DCMAKE_CXX_COMPILER=${hipcc}/bin/hipcc"
            "-DSTRATA_VISION_HIP_ARCHS=${lib.concatStringsSep ";" arch}"
          ]}
          cmake --build build-vision --target strata-vision -j
          cp build-vision/strata-vision-hip $out/engine/strata-vision-hip 2>/dev/null ||
            cp build-vision/strata-vision $out/engine/strata-vision-hip
        ''
      }

      python3 $src/packaging/package_engine.py --src $out/engine \
        --out $out --backend hip --version ${version} \
        ${archArgs} \
        --platform linux-x86_64
      runHook postInstall
    '';

    postFixup = ''
      wrapProgram $out/engine/*/strata \
        --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath runtime}
    '';

    meta = with lib; {
      description = "Strata's AMD (HIP) engine";
      license = licenses.mit;
      maintainers = [];
      mainProgram = "strata";
      platforms = platforms.linux;
    };
  }
