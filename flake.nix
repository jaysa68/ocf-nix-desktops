{
  description = "NixOS desktop configuration for the Open Computing Facility";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    ocflib.url = "github:ocf/ocflib";
    ocf-sync-etc.url = "github:ocf/etc";
    ocf-utils = {
      url = "github:ocf/utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wayout = {
      url = "github:ocf/wayout";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, ocflib, ocf-sync-etc, ocf-utils, wayout }:
    let
      # ================
      # nixpkgs overlays
      # ================

      pkgs-x86_64-linux = import nixpkgs {
        system = "x86_64-linux";
        config = { allowUnfree = true; };
        overlays = [
          ocflib.overlays.default
          ocf-sync-etc.overlays.default
          (final: prev: {
            ocf.utils = ocf-utils.packages.x86_64-linux.default;
            ocf.wayout = wayout.packages.x86_64-linux.default;
            ocf.plasma-applet-commandoutput = prev.callPackage ./pkgs/plasma-applet-commandoutput.nix { };
            ocf.catppuccin-sddm = prev.qt6Packages.callPackage ./pkgs/catppuccin-sddm.nix { };
          })
        ];
      };

      # ========================
      # NixOS Host Configuration
      # ========================

      # Put modules common to all hosts here.
      commonModules = [
        ./modules/ocf/auth.nix
        ./modules/ocf/graphical.nix
        ./modules/ocf/network.nix
        ./profiles/base.nix
      ];

      # Put modules for specific hosts here.
      hosts = nixpkgs.lib.concatMapAttrs
        (filename: _: rec {
          ${nixpkgs.lib.nameFromURL filename "."} = [
            ./hosts/${filename}
          ];
        })
        (builtins.readDir ./hosts);

      # =====================
      # Colmena Configuration
      # =====================

      colmena = builtins.mapAttrs
        (host: modules: {
          imports = commonModules ++ modules;
          deployment.targetHost = "${host}.ocf.berkeley.edu";
          deployment.buildOnTarget = true;
          deployment.targetUser = "root";
          deployment.allowLocalDeployment = true;
        })
        hosts;

      nixosConfigurations = builtins.mapAttrs
        (host: config: nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          pkgs = pkgs-x86_64-linux;
          modules = config.imports;
        })
        colmena;

      directOutputs = {
        inherit nixosConfigurations;

        colmena = colmena // {
          meta = { nixpkgs = pkgs-x86_64-linux; };
        };
      };

      # =======================
      # Dev Shell Configuration
      # =======================

      systemOutputs = flake-utils.lib.eachDefaultSystem
        (system:
          let pkgs = import nixpkgs { inherit system; }; in
          {
            devShells.default = pkgs.mkShell {
              packages = [ pkgs.colmena ];
            };

            packages.bootstrap = pkgs.callPackage ./bootstrap { };
            formatter = pkgs.nixpkgs-fmt;
          }
        );
    in
    directOutputs // systemOutputs;
}
