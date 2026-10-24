{
  version ? "",
  withVision ? true,
  arch ? ["75-real" "86-real" "89-real" "120-real" "120-virtual"],
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
}: let
  strip = a: lib.removeSuffix "-virtual" (lib.removeSuffix "-real" a);
  mkArchList = lib.concatStringsSep ";";
in
  stdenv.mkDerivation {
    name = "strata-engine-cuda";
    src = ../..;
    inherit version;

    nativeBuildInputs = [
      makeWrapper
      python3
      uv
      cmake
      ninja
    ];

    buildInputs = [zlib cuda];

    buildPhase = let
      archFlags = mkArchList arch;
    in ''
      cudaArchFlag="-DCMAKE_CUDA_ARCHITECTURES=${archFlags}"
      cmake -S . -B engine-build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DSTRATA_GGML_DIR=${llama-cpp.src} \
        -DSTRATA_BUILD_TESTS=OFF \
        -DSTRATA_ENABLE_CUDA=ON \
        "$cudaArchFlag"
      cmake --build engine-build --target strata libstrata_kq.so -j

      ${
        lib.optionalString withVision ''
          cmake -S $src/tools/vision -B vision-build -G Ninja \
            -DCMAKE_BUILD_TYPE=Release -DSTRATA_PORTABLE=ON \
            -DLLAMA_DIR=${llama-cpp.src} -DSTRATA_VISION_CUDA=ON \
            "$cudaArchFlag"
          cmake --build vision-build --target strata-vision -j
        ''
      }
    '';

    installPhase = let
      # the manifest's --arch vocabulary: sm_<nn> (machine code) / compute_<nn> (PTX)
      manifestArches =
        lib.concatMap
        (a: let
          bare = strip a;
        in
          if lib.hasSuffix "-virtual" a
          then ["compute_${bare}"]
          else ["sm_${bare}"])
        arch;
    in ''
      mkdir -p $out/engine
      cp engine-build/strata .
      cp engine-build/libstrata_kq.so .

      python3 $src/packaging/collect_libs.py --binary strata \
        --search ${cuda}/lib --out .

      ${lib.optionalString withVision ''
        cp vision-build/bin/strata-vision .

        echo '${let
          archs = mkArchList (map strip arch);
        in
          builtins.toJSON {
            inherit version archs;
            cuda = cuda.version;
            vision_archs = archs;
          }}' > BUILD.json
      ''}

      python3 $src/packaging/package_engine.py --src . \
        --out $out/engine --backend cuda --version ${version} \
        --min-driver nvidia=580.65 \
        ${lib.concatStringsSep " " (map (a: "--arch ${a}") manifestArches)}
    '';

    postFixup = ''
      wrap() {
        wrapProgram $1   \
        --prefix CUDA_HOME : ${cuda} \
        --prefix CUDA_PATH : ${cuda} \
        --prefix CUDAHOSTCXX : ${stdenv.cc}/bin/c++ \
        --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath [stdenv.cc.cc.lib zlib]}
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
      description = "Strata's CUDA engine";
      license = licenses.mit;
      maintainers = [];
      mainProgram = "strata";
    };
  }
