{
  version ? "",
  withVision ? true,
  arch ? [],
  lib,
  stdenv,
  rocmPackages,
  llama-cpp,
  makeWrapper,
  python3,
  uv,
  cmake,
  ninja,
  zlib,
  ...
}: let
  rocmSet = rocmPackages;
  hipcc = rocmSet.clr;
  runtime = [hipcc rocmSet.rocblas rocmSet.hipblaslt];
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

    buildPhase = ''
      # runHook preBuild
      #
      # local buildCores=$NIX_BUILD_CORES
      # local flagsArray=("-j$buildCores")
      # concatTo flagsArray ninjaFlags ninjaFlagsArray
      # echoCmd 'build flags' "''${flagsArray[@]}"
      # TERM=dumb ninja "''${flagsArray[@]}"

      ${
        lib.optionalString withVision ''
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
        ''
      }
      # runHook postBuild
    '';

    installPhase = ''
      mkdir -p $out/engine
      ${lib.optionalString withVision ''
        cp build-vision/strata-vision-hip $out/engine/strata-vision-hip 2>/dev/null ||
          cp build-vision/strata-vision $out/engine/strata-vision-hip
      ''}

      # BUILD.json: the engine's build record (packaging/build_hip_linux.sh's heredoc after its build).
      printf '{"version": "%s", "source": "nix/engines/hip.nix", "archs": "%s", "rocm": "%s", "portable": true}\n' \
        "${version}" \
        "${lib.concatStringsSep ";" arch}" \
        "${rocmPackages.clr.version or "unknown"}" \
        > BUILD.json

      python3 $src/packaging/package_engine.py --src . \
        --out $out/engine --backend hip --version ${version} \
        ${lib.concatStringsSep " " (map (a: "--arch ${a}") arch)}
    '';

    postFixup = ''
      wrapProgram $out/engine/*/strata \
        --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath ([stdenv.cc.cc.lib zlib] ++ runtime)}
    '';

    meta = with lib; {
      description = "Strata's AMD (HIP) engine";
      license = licenses.mit;
      maintainers = [];
      mainProgram = "strata";
      platforms = platforms.linux;
    };
  }
