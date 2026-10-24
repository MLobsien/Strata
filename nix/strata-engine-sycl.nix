# The Intel Arc (SYCL) engine: the sycl/ CMake project built with Intel's DPC++ (icpx/icx).
#
# What the build needs (sycl/CMakeLists.txt, packaging/build_sycl_linux.sh):
#   icpx / icx 2026.1 or newer (the -fsycl compiler; the nix-derivable one is intel-llvm,
#   which src-builds LLVM: hours of build time, so override the toolchain arg with a pinned
#   binary oneAPI release if you want a faster route), oneMKL's SYCL BLAS domain
#   (-qmkl=sequential at both compile and link), the pinned llama.cpp checkout (ggml),
#   and at run time the level-zero loader + compute runtime, which stay the system's own
#   (the packaging recipe says so explicitly: "the level-zero loader and the compute runtime
#   stay the PC's own"; on NixOS that is /run/opengl-driver/lib, wired into the wrapper below).
#
# NOT YET BUILT ON REAL HARDWARE from this package: eval-only until someone runs
# `nix build .#strata-engine-sycl` on a machine with an Intel GPU and confirms the parity
# self-tests. Keep the derivation honest about that in its meta.
{
  lib,
  stdenv,
  cmake,
  ninja,
  makeWrapper,
  python3,
  llama-cpp,
  zlib,
  # the DPC++ compiler providing icpx / icx; nixpkgs' intel-llvm builds LLVM from source
  intel-llvm,
  # oneMKL: only the MKL SYCL BLAS domain (-qmkl) is needed. nixpkgs has no oneMKL; pass one in
  # from a pinned Intel release (see the comment at the top). TODO when the backend gets built.
  onemkl ? null,
  level-zero ? null,    # the runtime loader the engine dlopens; wired into the wrapper when set
  ...
}: let
  # real stdenv: the sycl project builds C++ only; no CUDA backendStdenv involvement here.
  # intel-llvm's clang++ is a plain compiler, the sycl-ness comes from -fsycl flags the CMake sets.
in
  assert onemkl == null -> lib.warn "strata-engine-sycl: onemkl is null; -qmkl=sequential links will fail at build time (oneMKL is not in nixpkgs; supply it from a pinned Intel oneAPI release)" true;
  assert level-zero == null -> lib.warn "strata-engine-sycl: level-zero is null; the runtime loader comes from /run/opengl-driver (fine on NixOS with an Intel GPU)" true;
  stdenv.mkDerivation {
    name = "strata-engine-sycl";

    src = ../.;

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
    buildInputs = [zlib] ++ (lib.filter (p: p != null) [onemkl level-zero]);

    installPhase = ''
      runHook preInstall
      mkdir -p $out/engine
      cp strata $out/engine/strata
      runHook postInstall
    '';

    postFixup = lib.optionalString (level-zero != null) ''
      wrapProgram $out/engine/strata \
        --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath [level-zero]}
    '';

    meta = with lib; {
      description = "Strata's Intel Arc (SYCL) engine";
      # The engine source follows the project's own LICENSE.
      license = licenses.mit;
      maintainers = [];
      mainProgram = "strata";
      # The honest status, for anyone reading the package before building it: not yet smoke-tested
      # on an Arc card from this derivation.
    };
  }
