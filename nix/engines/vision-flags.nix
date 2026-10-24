# The vision reader build flags, shared by the engine derivations. NOT a package of its own (the
# reader ships inside each engine's $out/engine when that engine's withVision is on); this is the
# flag set the engine's own multi-build cmake invocation adds for the tools/vision subproject.
#
# tools/vision is built from the SAME source checkout as the engine: the engines' installPhase
# runs a second `cmake -S tools/vision` with these flags, then copies the reader binary beside
# `strata` before package_engine.py writes the manifest (which is what makes the manifest include
# the reader: package_engine.py's `wanted()` takes `strata-vision` automatically).
{
  lib,
  ...
}: {
  # (backend, arch, toolchain paths) -> extra cmake flags for the tools/vision build
  flags = {
    backend,
    arch ? [],
    cuda ? null,
    hipcc ? null,
    intel-llvm ? null,
    llama-cpp,
  }: let
    cudaOn = backend == "cuda" && cuda != null;
    hipOn = backend == "hip" && hipcc != null;
    syclOn = backend == "sycl" && intel-llvm != null;
    metalOn = backend == "metal";
  in
    [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DSTRATA_PORTABLE=ON"          # AVX2 baseline: the release default (#411 #412 #419)
      "-DLLAMA_DIR=${llama-cpp.src}"
      "-DSTRATA_VISION_CUDA=${if cudaOn then "ON" else "OFF"}"
      "-DSTRATA_VISION_HIP=${if hipOn then "ON" else "OFF"}"
      "-DSTRATA_VISION_SYCL=${if syclOn then "ON" else "OFF"}"
      "-DSTRATA_VISION_METAL=${if metalOn then "ON" else "OFF"}"
    ]
    ++ lib.optionals cudaOn (lib.optional (arch != []) "-DCMAKE_CUDA_ARCHITECTURES=${lib.concatStringsSep ";" arch}")
    ++ lib.optionals hipOn [
      "-DCMAKE_C_COMPILER=${hipcc}/bin/hipcc"
      "-DCMAKE_CXX_COMPILER=${hipcc}/bin/hipcc"
      "-DSTRATA_VISION_HIP_ARCHS=${lib.concatStringsSep ";" arch}"
    ]
    ++ lib.optionals syclOn [
      "-DCMAKE_C_COMPILER=${intel-llvm}/bin/icx"
      "-DCMAKE_CXX_COMPILER=${intel-llvm}/bin/icpx"
    ];
}
