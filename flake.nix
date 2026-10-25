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

    version = "0.1.48";
    strata-engine-cuda = pkgs.callPackage ./nix/engines/cuda.nix {
      inherit
        version
        stdenv
        cuda
        ;
    };
    strata-engine-sycl = pkgs.callPackage ./nix/engines/sycl.nix {inherit version;};
    strata-engine-hip = pkgs.callPackage ./nix/engines/hip.nix {inherit version;};
    strata-terminal = pkgs.callPackage ./nix/terminal.nix {inherit version;};
    strata-app = pkgs.callPackage ./nix/app.nix {
      inherit version strata-terminal;
      strata-engine = strata-engine-cuda;
    };

    pkgsDarwin = import nixpkgs {
      system = "aarch64-darwin";
      config.allowUnfree = true;
    };
    strata-engine-metal = pkgsDarwin.callPackage ./nix/engines/metal.nix {inherit version;};
    strata-terminal-mac = pkgsDarwin.callPackage ./nix/terminal.nix {inherit version;};
    strata-app-mac = pkgsDarwin.callPackage ./nix/app.nix {
      inherit version;
      strata-terminal = strata-terminal-mac;
      strata-engine = strata-engine-metal;
    };
  in {
    devShells."${system}" = {
      default = (pkgs.mkShell.override {inherit stdenv;}) {
        packages = with pkgs; [
          # ./setup.sh: makes .venv and runs setup.py
          python3

          # setup.py's engine build. cmake/ninja from PATH: the pip wheels' binaries do not run on NixOS. cuda cmake ninja
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
      default = strata-terminal;
      inherit strata-engine-cuda strata-engine-sycl strata-engine-hip strata-terminal strata-app;
    };

    packages.aarch64-darwin = {
      default = strata-terminal-mac;
      inherit strata-engine-metal strata-terminal-mac strata-app-mac;
    };
  };
}
