{
  version ? "",
  withVision ? false,   # the sycl reader exists (STRATA_VISION_SYCL) but oneMKL is not in nixpkgs; off by default here
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

  # The SYCL port is its own CMake project under sycl/, not the repo root; the cmake hook takes
  # the source root via configureScript (this file sits in nix/, so ../sycl from its build dir).
  configureScript = "$src/sycl";   # absolute: the sycl/ subproject of this source checkout
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_C_COMPILER=${intel-llvm}/bin/icx"
    "-DCMAKE_CXX_COMPILER=${intel-llvm}/bin/icpx"
    "-DSTRATA_SYCL_PARITY=OFF"
    "-DSTRATA_GGML_DIR=${llama-cpp.src}"
  ];

  nativeBuildInputs = [python3 cmake ninja makeWrapper];
  buildInputs = [zlib] ++ lib.filter (p: p != null) [onemkl level-zero];

  # The vision reader compiles after the engine's normal cmake-hook build (postBuild); the
  # default buildPhase stays untouched.
  postBuild =
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

    python3 $src/packaging/package_engine.py --src $out/engine \
      --out $out --backend sycl --version ${version} \
      --platform linux-x86_64
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/engine/strata \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath (lib.filter (p: p != null) [level-zero])}
  '';

  meta = with lib; {
    description = "Strata's Intel Arc (SYCL) engine";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "strata";
  };
}
