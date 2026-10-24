{
  version ? "",
  withVision ? false,
  lib,
  stdenv,
  cmake,
  ninja,
  makeWrapper,
  python3,
  llama-cpp,
  zlib,
  intel-llvm ? null,
  onemkl ? null,
  level-zero ? null,
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

  nativeBuildInputs = [python3 cmake ninja makeWrapper];
  buildInputs = [zlib] ++ lib.filter (p: p != null) [onemkl level-zero];

  buildPhase = ''
    # runHook preBuild
    #
    # local buildCores=$NIX_BUILD_CORES
    # local flagsArray=("-j$buildCores")
    # concatTo flagsArray ninjaFlags ninjaFlagsArray
    # echoCmd 'build flags' "''${flagsArray[@]}"
    # TERM=dumb ninja "''${flagsArray[@]}"

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
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/engine
    cp strata $out/engine/strata
    ${lib.optionalString (withVision && intel-llvm != null) ''
      # stage the reader beside the engine; package_engine.py picks it up when it writes the manifest
      cp build-vision/strata-vision-sycl $out/engine/strata-vision-sycl 2>/dev/null ||
        cp build-vision/strata-vision $out/engine/strata-vision-sycl
    ''}

    # BUILD.json: the engine's build record (packaging/build_sycl_linux.sh line 54's echo).
    printf '{"version": "%s", "source": "nix/engines/sycl.nix", "sycl": "DPC++ via intel-llvm %s", "portable": false}\n' \
      "${version}" \
      "${intel-llvm.version or "unknown"}" \
      > BUILD.json

    python3 $src/packaging/package_engine.py --src $out/engine \
      --out $out --backend sycl --version ${version} \
      --platform linux-x86_64
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/engine/strata \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath (lib.filter (p: p != null) [stdenv.cc.cc.lib zlib level-zero])}
  '';

  meta = with lib; {
    description = "Strata's Intel Arc (SYCL) engine";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "strata";
  };
}
