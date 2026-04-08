{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        nixpkgs.follows = "nixpkgs";
      };
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      treefmt-nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        inherit (nixpkgs) lib;
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python312;

        workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
        overlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";
        };
        editableOverlay = workspace.mkEditablePyprojectOverlay {
          root = "$REPO_ROOT";
        };
        hacks = pkgs.callPackage pyproject-nix.build.hacks { };

        pyprojectOverrides = final: prev: {
          # Example overrides to fix build
          # psycopg2 = prev.psycopg2.overrideAttrs (old: {
          #   buildInputs = (old.buildInputs or [ ]) ++ [
          #     prev.setuptools
          #     pkgs.libpq.pg_config
          #   ];
          # });
          # casadi = hacks.nixpkgsPrebuild {
          #   from = pkgs.python312Packages.casadi;
          #   prev = prev.casadi;
          # };

          ## TODO: Add tests to package?
          ## Based on https://pyproject-nix.github.io/uv2nix/patterns/testing.html
          ## Doesn't seem to work, cypress-ticket-scraper package isn't found
          #cypress-ticket-scraper = prev.cypress-ticket-scraper.overrideAttrs (old: {
          #  passthru = old.passthru // {
          #    tests =
          #      let
          #        _virtualenv = final.mkVirtualEnv "cypress-ticket-scraper-pytest-env" workspace.deps.all // {
          #          cypress-ticket-scraper = [ "dev" ];
          #        };
          #      in
          #      (old.tests or { })
          #      // {
          #        pytest = pkgs.stdenv.mkDerivation {
          #          name = "${final.cypress-ticket-scraper.name}-pytest";
          #          inherit (final.cypress-ticket-scraper) src;
          #          nativeBuildInputs = [
          #            virtualenv
          #            _virtualenv
          #          ];
          #          dontConfigure = true;
          #          buildPhase = ''
          #            runHook preBuild
          #            pytest
          #            runHook postBuild
          #          '';
          #        };
          #      };
          #  };
          #});
        };

        pythonSet =
          (pkgs.callPackage pyproject-nix.build.packages {
            inherit python;
          }).overrideScope
            (
              lib.composeManyExtensions [
                pyproject-build-systems.overlays.wheel
                overlay
                pyprojectOverrides
              ]
            );

        editablePythonSet = pythonSet.overrideScope editableOverlay;
        virtualenv = editablePythonSet.mkVirtualEnv "cypress-ticket-scraper-dev-env" workspace.deps.all;

        inherit (pkgs.callPackages pyproject-nix.build.util { }) mkApplication;

        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
      in
      {
        packages = {
          cypress-ticket-scraper = mkApplication {
            venv = pythonSet.mkVirtualEnv "cypress-ticket-scraper-app-env" workspace.deps.default;
            package = pythonSet.cypress-ticket-scraper;
          };
          default = self.packages.${system}.cypress-ticket-scraper;
        };
        formatter = treefmtEval.config.build.wrapper;
        checks = {
          formatting = treefmtEval.config.build.check self;
          # Doesn't seem to work
          # pytest = editablePythonSet.cypress-ticket-scraper.passthru.tests.pytest;
        };
        devShells = {
          default = pkgs.mkShell {
            packages = [
              virtualenv
              pkgs.uv
              pkgs.sphinx
              pkgs.git
            ];
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON = editablePythonSet.python.interpreter;
              UV_PYTHON_DOWNLOADS = "never";
            }
            // lib.optionalAttrs pkgs.stdenv.isLinux {
              LD_LIBRARY_PATH = lib.makeLibraryPath pkgs.pythonManylinuxPackages.manylinux1;
            };
            shellHook = ''
              unset PYTHONPATH
              export REPO_ROOT=$(git rev-parse --show-toplevel)
              . ${virtualenv}/bin/activate
            '';
          };
        };
      }
    )
    // {
      nixosModule =
        {
          lib,
          pkgs,
          config,
          ...
        }:
        with lib;
        let
          cfg = config.services.cypress-ticket-scraper;
          defaultUser = "cypress_ticket_scraper";
          defaultGroup = defaultUser;
        in
        {
          options.services.cypress-ticket-scraper = {
            enable = mkEnableOption (lib.mdDoc "Scrape ticket price data from Cypress Mountain");

            dataDir = mkOption {
              type = types.str;
              description = mdDoc ''
                Path to store dumped data to
              '';
            };

            interval = mkOption {
              type = types.str;
              default = "*-*-* 08:00:00";
              description = lib.mdDoc ''
                Systemd OnCalendar value for when to do a scrape
              '';
            };
          };

          config = mkIf cfg.enable {
            users.users.${defaultUser} = {
              group = defaultGroup;
              # Is this important?
              #uid = config.ids.uids.inventree;
              # Seems to be required with no uid set
              isSystemUser = true;
              description = "cypress-ticket-scraper user";
            };

            users.groups.${defaultGroup} = {
              # Is this important?
              #gid = config.ids.gids.inventree;
            };
            systemd.services.cypress-ticket-scraper = {
              description = "Cypress Mountain ticket price scraper";
              startLimitIntervalSec = 300;
              startLimitBurst = 5;
              serviceConfig = {
                Type = "oneshot";
                RestartSec = 60;
                Restart = "on-failure";
                User = defaultUser;
                Group = defaultGroup;
                ExecStart = "${pkgs.writers.writeBash "cypress-ticket-scraper-run" ''
                  mkdir -p ${cfg.dataDir}
                  cd ${cfg.dataDir}
                  ${
                    self.packages.${pkgs.stdenv.hostPlatform.system}.cypress-ticket-scraper
                  }/bin/cypress-ticket-scraper
                ''}";
              };
            };
            systemd.timers.cypress-ticket-scraper = {
              wantedBy = [ "timers.target" ];
              partOf = [ "cypress-ticket-scraper.service" ];
              # TODO: can we use two values here to make it fire during the season?
              timerConfig.OnCalendar = [ cfg.interval ];
            };
          };
        };
    };
}
