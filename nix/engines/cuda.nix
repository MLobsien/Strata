{
  version ? "",
  withVision ? true,
  arch ? ["sm_75-real" "sm_86-real" "sm_89-real" "sm_120-real" "sm_120-virtual"],
  cuda,
  stdenv,
  lib,
  llama-cpp,
  makeWrapper,
  python3,
  uv,
  cmake,
  ninja,
  zlib,
  ...
}:
stdenv.mkDerivation {
  name = "strata-engine";
  src = ../..;
  inherit version;

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DSTRATA_GGML_DIR=${llama-cpp.src}"
    "-DSTRATA_ENABLE_CUDA=ON"
    "-DCMAKE_CUDA_ARCHITECTURES=${lib.concatStringsSep ";" arch}"
  ];

  nativeBuildInputs = [
    makeWrapper
    python3
    uv
    cmake
    ninja
  ];

  buildInputs = [zlib cuda];

  # The build phase override: the normal cmake+ninja engine build first (the same shape the
  # ninja hook's ninjaBuildPhase runs: parallel cores, ninjaFlags), then the vision reader's
  # own cmake configure/build when withVision is on. install stays staging-only.
  buildPhase = ''
    runHook preBuild

    local buildCores=1
    if [ "''${enableParallelBuilding}" ] || [ -z "''${enableParallelBuilding-1}" ]; then
      buildCores="$NIX_BUILD_CORES"
    fi
    local flagsArray=("-j$buildCores")
    concatTo flagsArray ninjaFlags ninjaFlagsArray
    echoCmd 'build flags' "''${flagsArray[@]}"
    TERM=dumb ninja "''${flagsArray[@]}"

    ${
    lib.optionalString withVision ''
      cmake -S $src/tools/vision -B build-vision -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DSTRATA_PORTABLE=ON \
        -DLLAMA_DIR=${llama-cpp.src} -DSTRATA_VISION_CUDA=ON \
        -DCMAKE_CUDA_ARCHITECTURES=${lib.concatStringsSep ";" arch}
      cmake --build build-vision --target strata-vision -j
    ''
    }
    runHook postBuild
  '';

  installPhase = let
    manifestArches =
      lib.concatMap
      (a: let
        bare = lib.removePrefix "sm_" (
          lib.removeSuffix "-virtual" (lib.removeSuffix "-real" a)
        );
      in
        if lib.hasSuffix "-virtual" a
        then ["compute_${bare}"]
        else ["sm_${bare}"])
      arch;
  in
    ''
      mkdir -p $out/engine
      cp strata $out/engine/strata
      cp libstrata_kq.so $out/engine/ 2>/dev/null || true
    ''
    + lib.optionalString withVision ''
      # stage the reader beside the engine; package_engine.py's wanted() picks it up
      cp build-vision/strata-vision strata-vision
    ''
    + ''
      python3 $src/packaging/package_engine.py --src . \
        --out $out/engine --backend cuda --version ${version} \
        --min-driver nvidia=580.65 \
        ${
        lib.concatStringsSep " " (map (a: "--arch ${a}") manifestArches)
      }
    '';

  postFixup = ''
    wrapProgram $out/engine/*/strata $out/engine/*/strata-vision \
    --prefix CUDA_HOME : ${cuda} \
    --prefix CUDA_PATH : ${cuda} \
    --prefix CUDAHOSTCXX : ${stdenv.cc}/bin/c++ \
    --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath [stdenv.cc.cc.lib zlib]}
  '';
}
