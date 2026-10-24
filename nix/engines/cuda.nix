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
}: let
  # The picture reader (strata-vision) is built INSIDE this derivation, from tools/vision in the
  # same checkout, with the SAME arch list as the engine: package_engine.py refuses a CUDA package
  # whose reader covers fewer cards than the engine (check_picture_reader, #3669), so an
  # arch-matched reader is what makes the package pass its own verification. The flags come from
  # the shared helper (nix/engines/vision-flags.nix).
  visionFlags = (import ./vision-flags.nix {inherit lib;}).flags;
in
  stdenv.mkDerivation {
    name = "strata-engine";
    src = ../..;
    inherit version;

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DSTRATA_GGML_DIR=${llama-cpp.src}"
      "-DSTRATA_ENABLE_CUDA=ON"
      # The archs list drives nvcc: NN-real entries become machine code for that generation,
      # the trailing NN-virtual embeds PTX (JITs on future cards). CUDA-arch names with suffixes
      # feed CMake directly; no stripping here (the manifest mapping strips them below).
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

    installPhase = let
      # The manifest's --arch vocabulary is the schema's human form: sm_<nn> for machine code,
      # compute_<nn> where the list had NN-virtual (PTX). The build arch "sm_75-real" becomes
      # manifest arch "sm_75"; "sm_120-virtual" becomes "compute_120".
      manifestArches =
        # sm_75-real -> sm_75 ; sm_120-real/x2 -> sm_120 + compute_120 once per virtual
        lib.concatMap
        (a:
          let bare = (lib.removePrefix "sm_" (lib.removeSuffix "-virtual" (lib.removeSuffix "-real" a)));
          in if lib.hasSuffix "-virtual" a
          then [ "compute_${bare}" ]
          else [ "sm_${bare}" ])
        arch;
    in ''
      runHook preInstall
      mkdir -p $out/engine
      cp strata $out/engine/strata
      cp libstrata_kq.so $out/engine/ 2>/dev/null || true

      ${
      lib.optionalString withVision ''
        # the picture reader, arch-matched; package_engine.py's wanted() picks it up beside strata
        cmake -S $src/tools/vision -B build-vision -G Ninja \
          ${lib.concatStringsSep " " (visionFlags {
            backend = "cuda";
            inherit arch;
            cuda = cuda;
            llama-cpp = llama-cpp;
          })}
        cmake --build build-vision --target strata-vision -j
        cp build-vision/strata-vision $out/engine/strata-vision
      ''
      }

      python3 $src/packaging/package_engine.py --src $out/engine \
        --out $out --backend cuda --version ${version} \
        --min-driver nvidia=580.65 \
        ${
        lib.concatStringsSep " " (map (a: "--arch ${a}") manifestArches)
      }
      runHook postInstall
    '';

    postFixup = ''
      wrapProgram $out/engine/*/strata \
      --prefix CUDA_HOME : ${cuda} \
      --prefix CUDA_PATH : ${cuda} \
      --prefix CUDAHOSTCXX : ${stdenv.cc}/bin/c++ \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath [stdenv.cc.cc.lib zlib]}
    '';
  }
