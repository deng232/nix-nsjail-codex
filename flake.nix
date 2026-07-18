{
  description = "NixOS nsjail wrappers for Codex agent sessions";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          pasta = pkgs.runCommand "pasta-for-nsjail" { } ''
            mkdir -p $out/bin
            ln -s ${pkgs.passt}/bin/passt $out/bin/pasta
          '';

          runtimePath = lib.makeBinPath [
            pkgs.bashInteractive
            pkgs.codex
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gnused
            pkgs.nsjail
            pkgs.passt
            pasta
            pkgs.python3
            pkgs.xdg-utils
          ];

          browserchannel = pkgs.stdenvNoCC.mkDerivation {
            pname = "browserchannel";
            version = "0.1.0";
            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              mkdir -p $out/bin
              substitute ${./scripts/browserchannel.sh} $out/bin/browserchannel \
                --subst-var-by runtime_path ${runtimePath}
              chmod +x $out/bin/browserchannel
            '';
          };

          mkNsJailWrapper =
            { name
            , defaultCommand
            }:
            pkgs.stdenvNoCC.mkDerivation {
              pname = name;
              version = "0.1.0";
              dontUnpack = true;
              dontBuild = true;

              installPhase = ''
                mkdir -p $out/bin
                substitute ${./scripts/nsjail-wrapper.sh} $out/bin/${name} \
                  --subst-var-by runtime_path ${runtimePath} \
                  --subst-var-by nsjail ${pkgs.nsjail}/bin/nsjail \
                  --subst-var-by python ${pkgs.python3}/bin/python3 \
                  --subst-var-by browserchannel ${browserchannel}/bin/browserchannel \
                  --subst-var-by config_template ${./config/nsjail.pbtxt.in} \
                  --subst-var-by default_command '${defaultCommand}'
                chmod +x $out/bin/${name}
              '';
            };

          nsjail-env = mkNsJailWrapper {
            name = "nsjail-env";
            defaultCommand = "${pkgs.bashInteractive}/bin/bash -l";
          };

          nsjail-codex = mkNsJailWrapper {
            name = "nsjail-codex";
            defaultCommand = "${pkgs.codex}/bin/codex";
          };
        in
        {
          default = nsjail-codex;
          inherit browserchannel nsjail-env nsjail-codex;
        });

      apps = forAllSystems (system:
        let
          packages = self.packages.${system};
        in
        {
          default = {
            type = "app";
            program = "${packages.nsjail-codex}/bin/nsjail-codex";
          };
          nsjail-env = {
            type = "app";
            program = "${packages.nsjail-env}/bin/nsjail-env";
          };
          nsjail-codex = {
            type = "app";
            program = "${packages.nsjail-codex}/bin/nsjail-codex";
          };
        });
    };
}
