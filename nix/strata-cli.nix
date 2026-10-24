{
  lib,
  stdenv,
  python3,
  makeWrapper,
  ...
}:
stdenv.mkDerivation {
  pname = "strata-cli";
  version = "0.2.3";

  src = ../.;

  nativeBuildInputs = [makeWrapper python3];
  dontConfigure = true;
  dontBuild = true;

  installPhase = let
    inherit (python3) sitePackages;

    pyEnv = python3.withPackages (
      p:
        with p; [
          numpy
          jinja2
          pyyaml
          requests
          psutil
          pillow
          regex
          truststore
          rich
          textual
        ]
    );
  in ''
    mkdir -p $out/${sitePackages} $out/bin

    ${python3}/bin/python3 packaging/package_terminal.py \
      --out $out/${sitePackages}

    makeWrapper ${pyEnv.interpreter} $out/bin/strata \
      --add-flags "$out/${sitePackages}/strata.py" \
      --set PYTHONPATH "$out/${sitePackages}"
  '';

  meta = {
    description = "Strata CLI";
    license = lib.licenses.mit;
    maintainers = [];
    mainProgram = "strata";
  };
}
