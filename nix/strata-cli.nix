# The Python part of Strata: the `strata` terminal command (strata.py -> strata_cli.cli.main) and the
# API server behind `strata serve` (serve/server.py). Pure Python, no CUDA, no compiled code of its own.
#
# The repo has no pyproject.toml, so this is not a Python package: it copies the needed source trees
# into the wrapper python's site-packages and installs a `strata` wrapper script around strata.py.
#
# Why a wrapper and not a build: strata.py's preflight insists that `strata serve` never installs
# anything and fails with a typed error listing the missing packages when the interpreter has none.
# The wrapper mirrors that contract at the nix level:
#   strata-cli        (addDeps = false): the stdlib-only commands. `strata serve` / `bench` refuse
#                       with that typed error. Good default for a control-plane-only machine.
#   strata-cli-full   (addDeps = true): the wrapper python becomes python3.withPackages (numpy,
#                       jinja2, pyyaml, requests, psutil, pillow, regex, truststore - the imports of
#                       serve/server.py), so `strata serve` starts. It still needs an ENGINE at
#                       runtime: point STRATA_COMPONENTS_DIR at an engine component folder, or hand
#                       the run config an "exe" that names the `strata` binary built by this flake's
#                       `strata` package.
#
# Runtime dependency this package cannot own: the CUDA driver library (libcuda.so.1). On NixOS it
# comes from /run/opengl-driver/lib; only the engine binary needs it, and it talks to the server
# over stdin/stdout, so the python package's closure can stay driver-free.
{
  lib,
  stdenv,
  python3,
  makeWrapper,
  # the individual packages the server imports; the light flavour passes the empty list
  numpy ? null,
  jinja2 ? null,
  pyyaml ? null,
  requests ? null,
  psutil ? null,
  pillow ? null,
  regex ? null,
  truststore ? null,
  addDeps ? false,
}: let
  sitePackages = python3.sitePackages;
  # The withPackages lambda takes the list directly, so a null filter makes one serverDeps per flavour.
  serverDeps = lib.filter (p: p != null) [numpy jinja2 pyyaml requests psutil pillow regex truststore];
  pyEnv = if addDeps then python3.withPackages (_: serverDeps) else python3;
in
  stdenv.mkDerivation {
    pname = "strata-cli";
    version = "0.2.3";

    src = ../.;

    # The trees the runtime imports. serve/ is only a runtime import for `strata serve`, but keeping
    # it in the light flavour keeps `strata serve --help` (stdlib imports) working.
    srcTrees = ["strata.py" "strata_cli" "strata_control" "serve"];

    nativeBuildInputs = [makeWrapper];
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/${sitePackages} $out/bin
      for t in $srcTrees; do
        cp -r "$src/$t" $out/${sitePackages}/
      done
      # strata.py is a plain script, not a console entry point; install our own runner.
      makeWrapper ${pyEnv.interpreter} $out/bin/strata \
        --add-flags "$out/${sitePackages}/strata.py" \
        --set PYTHONPATH "$out/${sitePackages}"
      runHook postInstall
    '';

    # The project's own contract, enforced at build time on both flavours:
    # stdlib-only commands must run without imports beyond the stdlib, and the listed runtime check
    # is the command a server machine would run next (it exits non-zero only on a bad install).
    installCheckPhase = ''
      runHook preInstallCheck
      $out/bin/strata --help > /dev/null
      $out/bin/strata doctor --help > /dev/null
      $out/bin/strata status --help > /dev/null
      runHook postInstallCheck
    '';
    doInstallCheck = true;

    meta = with lib; {
      description = "Strata's terminal command (the model setup / serve / monitor CLI)";
      license = licenses.mit;
      maintainers = [];
      mainProgram = "strata";
    };
  }
