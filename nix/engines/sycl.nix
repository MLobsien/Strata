{
  version ? "",
  withVision ? false,
  lib,
  stdenv,
  cmake,
  ninja,
  makeWrapper,
  patchelf,
  python3,
  llama-cpp,
  zlib,
  intel-llvm ? null,
  mkl ? null,
  level-zero,
  ...
}:
stdenv.mkDerivation {
  name = "strata-engine-sycl";

  src = ../..;

  configureScript = "$src/sycl";
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_C_COMPILER=${intel-llvm}/bin/icx"
    "-DCMAKE_CXX_COMPILER=${intel-llvm}/bin/icpx"
    "-DSTRATA_SYCL_PARITY=OFF"
    "-DSTRATA_GGML_DIR=${llama-cpp.src}"
  ];

  nativeBuildInputs = [python3 cmake ninja makeWrapper patchelf];
  buildInputs = [zlib] ++ lib.filter (p: p != null) [mkl level-zero];

  buildPhase = ''
    local buildCores=$NIX_BUILD_CORES
    local flagsArray=("-j$buildCores")
    concatTo flagsArray ninjaFlags ninjaFlagsArray
    echoCmd 'build flags' "''${flagsArray[@]}"
    TERM=dumb ninja "''${flagsArray[@]}"

    ${
      lib.optionalString (withVision && intel-llvm != null) ''
        cmake -S $src/tools/vision -B build-vision -G Ninja \
          ${lib.concatStringsSep " " [
          "-DCMAKE_BUILD_TYPE=Release"
          "-DSTRATA_PORTABLE=ON"
          "-DLLAMA_DIR=${llama-cpp.src}"
          "-DSTRATA_VISION_SYCL=ON"
          "-DCMAKE_C_COMPILER=${intel-llvm}/bin/icx"
          "-DCMAKE_CXX_COMPILER=${intel-llvm}/bin/icpx"
        ]}
        cmake --build build-vision --target strata-vision -j
      ''
    }
  '';

  installPhase = ''
    mkdir -p $out/engine

    cp engine-build/strata engine-build/libstrata_kq.so .

    python3 $src/packaging/collect_libs.py --binary strata \
      --search ${intel-llvm}/lib \
      --search ${mkl}/lib \
      --out .

    ${lib.optionalString withVision ''
      cp vision-build/bin/strata-vision .
    ''}

    python3 $src/packaging/package_engine.py --src . \
      --out $out/engine --backend sycl --version ${version} \
      --platform linux-x86_64
  '';

  postFixup = ''
    wrap() {
      wrapProgram $out/engine/*/strata \
       --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath [stdenv.cc.cc.lib zlib level-zero]}
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
    description = "Strata's Intel Arc (SYCL) engine";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "strata";
  };
}
