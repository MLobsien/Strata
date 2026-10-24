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
  mkBare = a: lib.removeSuffix "-virtual" (lib.removeSuffix "-real" a);
in
  stdenv.mkDerivation {
    name = "strata-engine";
    src = ../..;
    inherit version;

    # Skip the cmake hook's configure: nothing it does for this project survives it (in-dir cd
    # semantics, hard-coded install paths, injected flags, the -GNinja duplication) and the phases
    # below take explicit absolute flags instead. The parallel-core count is honoured by -j.
    dontUseCmakeConfigure = true;

    nativeBuildInputs = [
      makeWrapper
      python3
      uv
      cmake
      ninja
    ];

    buildInputs = [zlib cuda];

    buildPhase = ''
      cudaArchFlag="-DCMAKE_CUDA_ARCHITECTURES=${lib.concatStringsSep ";" arch}"
      cmake -S . -B engine-build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DSTRATA_GGML_DIR=${llama-cpp.src} \
        -DSTRATA_BUILD_TESTS=OFF \
        -DSTRATA_ENABLE_CUDA=ON \
        "$cudaArchFlag"
      cmake --build engine-build --target strata libstrata_kq.so -j

      ${
        lib.optionalString withVision ''
          cudaArchFlag="-DCMAKE_CUDA_ARCHITECTURES=${lib.concatStringsSep ";" arch}"
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
          bare = lib.removeSuffix "-virtual" (lib.removeSuffix "-real" a);
        in
          if lib.hasSuffix "-virtual" a
          then ["compute_${bare}"]
          else ["sm_${bare}"])
        arch;
    in ''
      mkdir -p $out/engine
      cp engine-build/strata .
      cp engine-build/libstrata_kq.so .

      cp ${cuda}/lib/libcublas.so.13 ${cuda}/lib/libcublasLt.so.13 \
        ${cuda}/lib/libcudart.so.13 .

      ${lib.optionalString withVision ''
        cp vision-build/bin/strata-vision .

        echo '${let
          archs = lib.concatStringsSep ";" (map (a: lib.removeSuffix "-virtual" (lib.removeSuffix "-real" a)) arch);
        in
          builtins.toJSON {
            inherit version;
            cuda = cuda.version;
          }}' > BUILD.json
      ''}

      # BUILD.json: the engine's build record (what packaging/build_cuda_linux.sh writes after its
      # build; package_engine.py copies it into the package, and check_picture_reader reads
      # vision_archs to confirm the reader covers the engine's cards, #3669). archs here is the
      # manifest's vocabulary (the -real/-virtual suffixes stripped).
      printf '{"version": "%s", "source": "nix/engines/cuda.nix", "archs": "%s", "cuda": "%s", "portable": true, "vision_archs": "%s"}\n' \
        "${version}" \
        "${lib.concatStringsSep ";" (map (a: lib.removeSuffix "-virtual" (lib.removeSuffix "-real" a)) arch)}" \
        "${cuda.version}" \
        "${lib.concatStringsSep ";" (map (a: lib.removeSuffix "-virtual" (lib.removeSuffix "-real" a)) arch)}" \
        > BUILD.json

      python3 $src/packaging/package_engine.py --src . \
        --out $out/engine --backend cuda --version ${version} \
        --min-driver nvidia=580.65 \
        ${lib.concatStringsSep " " (map (a: "--arch ${a}") manifestArches)}
    '';

    postFixup = ''
      wrapProgram $out/engine/*/strata $out/engine/*/strata-vision \
      --prefix CUDA_HOME : ${cuda} \
      --prefix CUDA_PATH : ${cuda} \
      --prefix CUDAHOSTCXX : ${stdenv.cc}/bin/c++ \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath [stdenv.cc.cc.lib zlib]}

      substituteInPlace $out/engine/*/engine-component.json \
        --replace '"path": "strata"' '"path": ".strata-wrapped" ${
        lib.optionalString withVision ''--replace '"path": "strata-vision"' '"path": ".strata-vision-wrapped"' ''
      }
    '';
  }
