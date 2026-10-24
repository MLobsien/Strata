# The Strata Terminal / CLI package for nix.
#
# packaging/package_terminal.py is the layout authority for the distributed archive, but its staged
# bundle embeds a standalone CPython that cannot execute inside this sandbox (it expects the FHS
# /lib64 loader). This derivation replicates the script's --skip-deps staging in plain bash, using
# nix's python3 plus the runtime deps (the wrapper interpreter below): what the APP path needs is the
# staged control tree, not a runnable embedded interpreter. The launcher and prying deps come from nix.
{
  version ? "0.2.3",
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  ...
}: let
  inherit (python3) sitePackages;

  pyEnv = python3.withPackages (p:
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
    ]);
in
  stdenvNoCC.mkDerivation {
    name = "strata-cli";
    inherit version;

    src = ../.;

    passthru = {inherit sitePackages;};

    nativeBuildInputs = [makeWrapper];
    dontConfigure = true;
    dontBuild = true;

    # The payload lists verbatim from packaging/package_terminal.py (PAYLOAD, TOOLS_SUBSET,
    # INSTALLER_FILES): a staged tree is what the desktop app's installPhase symlinks as
    # resources/control, via passthru.sitePackages.
    installPhase = ''
      dst=$out/${sitePackages}
      mkdir -p $dst $out/bin

      for item in \
        strata.py \
        strata_control \
        strata_cli \
        serve \
        requirements.txt \
        requirements-monitor.txt \
        docs/MANAGEMENT_PROTOCOL.md \
        docs/TERMINAL_LAUNCH.md \
        data/gguf_fingerprints.json \
        bench/prompts/standard-v1
      do
        if [ -d "$item" ]; then
          cp -r --no-preserve=mode,ownership "$item" "$dst/"
        else
          install -Dm644 "$item" "$dst/$item"
        fi
      done

      mkdir -p $dst/tools
      for item in strata_tokenizer.py gguf_reader.py dflash2_pack.py; do
        install -m644 "tools/$item" "$dst/tools/$item"
      done

      # the installer payload (setup.py + ref/load.py + its tools/ imports + data/)
      install -Dm644 setup.py "$dst/setup.py"
      install -Dm644 ref/load.py "$dst/ref/load.py"
      for item in strata_mcp iq_pack strata_pack pack_index mtp_fetch mtp_pack mtp_rt draft_vocab \
                  strata_tokenizer gguf_reader calibrate; do
        install -m644 "tools/$item.py" "$dst/tools/$item.py"
      done
      cp -r --no-preserve=mode,ownership data $dst/data

      mkdir -p $dst/bin
      install -m755 bin/strata "$dst/bin/strata"

      (echo "$version"; echo; ) > $dst/VERSION

      makeWrapper ${pyEnv.interpreter} $out/bin/strata \
        --add-flags "$dst/strata.py" \
        --set PYTHONPATH "$dst"
    '';

    meta = {
      description = "Strata Terminal / CLI";
      license = lib.licenses.mit;
      maintainers = [];
      mainProgram = "strata";
    };
  }
