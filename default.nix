# The Strata engine: the C++/CUDA `strata` binary served as a subprocess by the Python server.
#
# Backend support (main CMakeLists.txt):
#   cudaSupport = true   -> -DSTRATA_ENABLE_CUDA=ON, gives the `strata` engine (and its helper tools).
#   cudaSupport = false  -> NO engine target exists upstream: without CUDA or HIP the main build makes
#                           only helper tools and CPU parity testers (`strata-gguf`, `strata-plan`,
#                           `iq_avx*_parity`, ...). The Mac engine is a separate CMake project in
#                           metal/ (Apple Silicon only), the Intel one in sycl/. A `strata-cpu`
#                           package therefore produces the helper tools, not a servable engine; it is
#                           useful to check the CPU-only compile on a machine without CUDA in CI.
{
  cudaSupport ? true,
  lib,
  cudaPackages_13_0,
  llama-cpp,
  makeWrapper,
  python3,
  uv,
  cmake,
  ninja,
  zlib,
  ...
}: let
  # setup.py wants CUDA 13.0: the ready-made engine is built with 13.0.88, and 13.2.0/13.2.1 miscompile for sm_120.
  cudaPackages = cudaPackages_13_0;
  # One merged toolkit root (bin/nvcc, include/, lib/ with cudart and cuBLAS) for CUDA_HOME / CUDAToolkit_ROOT.
  cuda = cudaPackages.cudatoolkit;
  # The gcc that this nvcc supports as its host compiler.
  stdenv = cudaPackages.backendStdenv;

  # cmakeFlags for the flavour. The CUDA build must not silently degrade to a CPU-only configure: with
  # cudaSupport = false there is no -DSTRATA_ENABLE_CUDA and the `strata` target simply does not exist.
  # installPhase below fails loudly in that case instead of installing an empty package.
  extraFlags = lib.optionals cudaSupport ["-DSTRATA_ENABLE_CUDA=ON"];
in
  lib.warnIf (!cudaSupport) "strata-cpu: no engine binary exists without CUDA (see nix/default.nix head comment); this package installs the CPU helper tools only"
  stdenv.mkDerivation {
    name = if cudaSupport then "strata" else "strata-cpu-helpers";
    src = ./.;

    cmakeFlags =
      ["-DSTRATA_GGML_DIR=${llama-cpp.src}" "-DCMAKE_BUILD_TYPE=Release"] ++ extraFlags;

    nativeBuildInputs = [
      makeWrapper
      python3
      uv
      cmake
      ninja
    ];

    # CUDA libs only when the CUDA build needs them; zlib always (ggml links it).
    buildInputs = lib.optionals cudaSupport [cuda] ++ [zlib];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/lib
      if [ -f strata ]; then
        cp strata $out/bin/strata
        cp libstrata_kq.so $out/lib/libstrata_kq.so
      else
        # The CPU-only configure makes helper tools and parity testers only (no engine target exists
        # upstream without CUDA/HIP). Install them so the flavour is testable on a CUDA-less builder.
        for t in strata-gguf strata-plan strata-dequant; do
          test -f "$t" && cp "$t" $out/bin/
        done
      fi
      runHook postInstall
    '';

    postFixup = lib.optionalString cudaSupport ''
      wrapProgram $out/bin/strata \
      --prefix CUDA_HOME : ${cuda} \
      --prefix CUDA_PATH : ${cuda} \
      --prefix CUDAHOSTCXX : ${stdenv.cc}/bin/c++ \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath [stdenv.cc.cc.lib zlib]}
    '';
  }
