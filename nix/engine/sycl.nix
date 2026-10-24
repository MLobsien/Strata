{
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
  configureScript = "../sycl";
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_C_COMPILER=${intel-llvm}/bin/icx"
    "-DCMAKE_CXX_COMPILER=${intel-llvm}/bin/icpx"
    "-DSTRATA_SYCL_PARITY=OFF"
    "-DSTRATA_GGML_DIR=${llama-cpp.src}"
  ];

  nativeBuildInputs = [python3 cmake ninja makeWrapper];
  buildInputs = [zlib] ++ lib.filter (p: p != null) [onemkl level-zero];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/engine
    cp strata $out/engine/strata
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
