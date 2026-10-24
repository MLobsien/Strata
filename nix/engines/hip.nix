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
  hipcc = rocmPackages.clr;
  runtime = with rocmPackages; [clr rocblas hipblaslt];

  mkArchList = lib.concatStringsSep ";";
  archs = mkArchList arch;
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
      "-DCMAKE_HIP_ARCHITECTURES=${archs}"
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
      local buildCores=$NIX_BUILD_CORES
      local flagsArray=("-j$buildCores")
      concatTo flagsArray ninjaFlags ninjaFlagsArray
      echoCmd 'build flags' "''${flagsArray[@]}"
      TERM=dumb ninja "''${flagsArray[@]}"

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
            "-DSTRATA_VISION_HIP_ARCHS=${archs}"
          ]}
          cmake --build build-vision --target strata-vision -j
        ''
      }
    '';

    installPhase = ''
      mkdir -p $out/engine

      cp engine-build/strata .
      cp engine-build/libstrata_kq.so .

      python3 $src/packaging/collect_libs.py --binary strata \
        --search ${rocmPackages}/lib \
        --search ${rocmPackages.clr}/lib \
        --out .

      echo '${lib.toJSON {
        inherit version archs;
        source = "nix/engines/hip.nix";
        rocm = hipcc.version;
      }}' > BUILD.json

      ${lib.optionalString withVision ''
        cp vision-build/bin/strata-vision .
      ''}

      python3 $src/packaging/package_engine.py --src . \
        --out $out/engine --backend hip --version ${version} \
        ${lib.concatStringsSep " " (map (a: "--arch ${a}") arch)}
    '';

    postFixup = ''
      wrap() {
        wrapProgram $1 \
         --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath ([stdenv.cc.cc.lib zlib] ++ runtime)}
      }
      wrap $out/engine/*/strata
      ${lib.optionalString withVision ''
        wrap $out/engine/*/strata-vision
      ''}

      substituteInPlace $out/engine/*/engine-component.json \
        --replace '"path": "strata"' '"path": ".strata-wrapped"' ${
        lib.optionalString withVision ''--replace '"path": "strata-vision"' '"path": ".strata-vision-wrapped"' ''
      }
    '';

    meta = with lib; {
      description = "Strata's AMD (HIP) engine";
      license = licenses.mit;
      maintainers = [];
      mainProgram = "strata";
      platforms = platforms.linux;
    };
  }
