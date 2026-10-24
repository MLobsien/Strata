{
  version ? "",
  withVision ? true,
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
  ];

  nativeBuildInputs = [
    makeWrapper
    python3
    uv
    cmake
    ninja
  ];

  buildInputs = [zlib cuda];

  installPhase = ''
    mkdir -p $out/engine
    cp strata $out/engine/strata
    cp libstrata_kq.so $out/engine/libstrata_kq.so
    cp ${cuda}/lib/libcublas.so.13 ${cuda}/lib/libcublasLt.so.13 \
      ${cuda}/lib/libcudart.so.13 $out/engine/

    python3 packaging/package_engine.py --src $out/engine \
      --out $out/engine --backend cuda --version ${version} \
      --min-driver nvidia=580.65
  '';

  postFixup = ''
    wrapProgram $out/engine/strata \
    --prefix CUDA_HOME : ${cuda} \
    --prefix CUDA_PATH : ${cuda} \
    --prefix CUDAHOSTCXX : ${stdenv.cc}/bin/c++ \
    --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath [stdenv.cc.cc.lib zlib]}
  '';
}
