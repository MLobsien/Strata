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
    # Keep two instances of nixpkgs: one with CUDA for the engine, one plain for everything else, because
    # config.cudaSupport = true makes the whole package set pull the CUDA toolkit (and needs allowUnfree).
    pkgsNoCuda = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      config.cudaSupport = false;
    };

    strata = pkgs.callPackage ./. {};

    # The Python CLI / server (strata.py and its three libraries). Pure Python, no CUDA, no machine code.
    # Two flavours: strata-cli is stdlib-only; strata-cli-full adds the packages `strata serve` imports.
    # callPackage supplies stdenv/python3/makeWrapper/lib from pkgsNoCuda; the python packages for the
    # server's imports come from pkgsNoCuda.python3Packages, passed explicitly because callPackage
    # cannot see inside the callPackage'd python3.withPackages (the withPackages lambda's
    # arguments are a fresh scope, not the outer one).
    strata-cli = pkgsNoCuda.callPackage ./nix/strata-cli.nix {addDeps = false;};
    strata-cli-full = pkgsNoCuda.callPackage ./nix/strata-cli.nix {
      addDeps = true;
      inherit (pkgsNoCuda.python3Packages) numpy jinja2 pyyaml requests psutil pillow regex truststore;
    };
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
      default = strata;
      inherit strata;
      # CPU-only engine: no CUDA toolkit in the build, no -DSTRATA_ENABLE_CUDA (the CMake default).
      # Useful for CI and for machines without a supported GPU; it cannot serve models by itself.
      strata-cpu = strata.override {cudaSupport = false;};
      inherit strata-cli strata-cli-full;
    };
  };
}
