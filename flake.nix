{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    poetry2nix,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        inherit
          (poetry2nix.lib.mkPoetry2Nix {inherit pkgs;})
          mkPoetryEnv
          mkPoetryApplication
          defaultPoetryOverrides
          ;
      in {
        packages = {
          cypress-ticket-scraper = mkPoetryApplication {projectDir = self;};
          default = self.packages.${system}.cypress-ticket-scraper;
        };
        #devShells.default = pkgs.mkShell {
        #  buildInputs = [
        #    poetryEnv
        #  ];
        #};
        devShells.poetry = pkgs.mkShell {
          buildInputs = [
            # Required to make poetry shell work properly
            pkgs.bashInteractive
          ];
          packages = [pkgs.poetry];
        };
      }
    )
    // {
      nixosModule = {
        lib,
        pkgs,
        config,
        ...
      }:
        with lib; let
          cfg = config.services.cypress-ticket-scraper;
          defaultUser = "cypress-ticket-scraper";
          defaultGroup = defaultUser;
        in {
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
                  cd ${cfg.dataDir}
                  ${self.packages.${pkgs.system}.cypress-ticket-scraper}/bin/cypress-ticket-scraper
                ''}";
              };
            };
            systemd.timers.cypress-ticket-scraper = {
              wantedBy = ["timers.target"];
              partOf = ["cypress-ticket-scraper.service"];
              # TODO: can we use two values here to make it fire during the season?
              timerConfig.OnCalendar = [cfg.interval];
            };
          };
        };
    };
}
