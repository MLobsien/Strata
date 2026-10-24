{
  description = "Nix environment for Strata";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      # Allow NVIDIA's CUDA toolkit (nvcc, cudart, cuBLAS, ...).
      config.allowUnfree = true;
      config.cudaSupport = true;
    };

    # setup.py wants CUDA 13.0: the ready-made engine is built with 13.0.88, and 13.2.0/13.2.1 miscompile for sm_120.
    cudaPackages = pkgs.cudaPackages_13_0;
    # One merged toolkit root (bin/nvcc, include/, lib/ with cudart and cuBLAS) for CUDA_HOME / CUDAToolkit_ROOT.
    cuda = cudaPackages.cudatoolkit;
    # The gcc that this nvcc supports as its host compiler.
    stdenv = cudaPackages.backendStdenv;

    # The engine backends, one flake attr per backend; see nix/strata-engines.nix for the layout.
    # SYCL is eval-only until someone intentionally starts its build (intel-llvm src-builds LLVM:
    # hours); the CUDA engine keeps its old default.
    strata-engine-cuda = pkgs.callPackage ./nix/strata-engine-cuda.nix {};
    # The sycl backend; its toolchain is overridable (see nix/strata-engine-sycl.nix: intel-llvm src-builds
    # LLVM for hours, later derivations may pin a binary oneAPI release instead).
    strata-engine-sycl = pkgs.callPackage ./nix/strata-engine-sycl.nix {};
    # Documentation-only index of the engines (a plain attrset, nothing is built by it):
    strata-engines = {
      cuda = strata-engine-cuda;
      inherit strata-engine-sycl;
      # Apple Silicon's engine deliberately has no derivation on a Linux nixpkgs instance:
      # metal/CMakeLists.txt FATAL_ERRORs on any non-Apple platform, and the honest answer is
      # "use a Mac nixpkgs (or the packaging/mac recipes)", not a derivation that never builds.
      # metal = null;   # See the comment block in nix/strata-engines.nix.
    };
    strata-cli = pkgs.callPackage ./nix/strata-cli.nix {strata-engine = strata-engine-cuda;};
  in {
    devShells."${system}" = {
      default = (pkgs.mkShell.override {inherit stdenv;}) {
        packages = with pkgs; [
          # ./setup.sh: makes .venv and runs setup.py
          python3

          # setup.py's engine build. cmake/ninja from PATH: the pip wheels' binaries do not run on NixOS.
          cuda
          cmake
          ninja
        ];

        shellHook = ''
          export CUDA_HOME=${cuda}
          export CUDA_PATH=${cuda}
          export CUDAHOSTCXX=${stdenv.cc}/bin/c++
          # The pip wheels in .venv (numpy, pillow, ...) need libstdc++ and zlib; the engine needs the driver's libcuda.
          export LD_LIBRARY_PATH=/run/opengl-driver/lib:${pkgs.lib.makeLibraryPath [stdenv.cc.cc.lib pkgs.zlib]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        '';
      };
    };

    packages.${system} = {
      default = strata-cli;
      inherit strata-engine-cuda strata-engine-sycl strata-cli;
      # The engine index is a documentation attrset, not a package: it lives beside packages, not in them.
      # (strata-engines = { cuda; sycl; metal = documented refusal }) at the top of this file.
    };
  };
}
