# Backend-aware strata-engine packages: cuda / sycl / (documented) metal.
#
# The engine's CMake offers:
#   * the CUDA engine: the main CMakeLists.txt with -DSTRATA_ENABLE_CUDA=ON (NVIDIA/Windows + Linux).
#   * the Intel Arc engine: sycl/, a separate CMake project (icpx from Intel's oneAPI DPC++, oneMKL,
#     -fsycl; GPU code JIT from SPIR-V unless STRATA_SYCL_AOT names a device). See sycl/CMakeLists.txt
#     and packaging/build_sycl_linux.sh; docs/INTEL_ARC.md has the platform story.
#   * the Apple Silicon engine: metal/, a separate CMake project that FATAL_ERRORs on any non-Apple
#     platform and needs metal-cpp headers + macOS frameworks. There is deliberately no Linux Metal
#     build: no derivation here, just the refusal documented below and in `examples`.
#
# The three are separate derivations, not default flags on one: their toolchains have nothing in
# common (nvcc + backendStdenv vs icpx vs Apple clang + metal-cpp), and conflating them hides which
# toolkit a given `strata` binary was made with.
# Packages only until explicitly built: every derivation here is eval-only by default and any real
# build is started by whoever wants it (`nix build .#strata-engine-sycl`), because intel-llvm's
# source build of LLVM takes hours and the sycl backend has not yet been tried on this machine.
{
  lib,
  stdenv,
  callPackage,
  cudaPackages_13_0,
  llama-cpp,
  makeWrapper,
  python3,
  uv,
  cmake,
  ninja,
  zlib,
  # SYCL backend: the DPC++ toolchain. nixpkgs' intel-llvm builds LLVM from source (hours); override
  # this to point at a pinned binary oneAPI release if that is preferred on a given machine.
  intel-llvm,
  ...
}:
{
  # CUDA engine: the only backend a plain `nixpkgs.callPackage` sees, because cudaPackages_13_0 +
  # backendStdenv come from the CUDA-flavoured nixpkgs instance the flake calls this module with.
  cuda = callPackage ./strata-engine-cuda.nix {};

  # Intel Arc engine (sycl/). NOT verified on hardware yet: the solo-build of intel-llvm was started
  # but interrupted; if it produces an icpx on your machine, `nix build .#strata-engine-sycl` runs the
  # sycl/ CMake project against a llama.cpp checkout pin. GPU code is JIT from SPIR-V (no AOT target
  # sealed in), so it is the release-recipe default build (Alchemist + Battlemage).
  sycl = callPackage ./strata-engine-sycl.nix {inherit intel-llvm;};

  # Apple Silicon engine: NOT PROVIDABLE from a Linux nixpkgs instance. metal/CMakeLists.txt's first
  # gate is `if(NOT APPLE) FATAL_ERROR`; the Apple packaging path is metal/setup_mac.py + the
  # packaging/mac recipes, not nix. There is no derivation on purpose; a fake one would mislead
  # (a Mac user would end up with a package that never built).
  #
  #   metal = <a macos-arm64 nixpkgs instance>.callPackage ./strata-engine-metal.nix {}   # future
}
