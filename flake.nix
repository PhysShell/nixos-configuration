{
  description = "Unified NixOS flake — desktop (physshell) & WSL";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, agenix, nixos-wsl, ... }:
  let
    system = "x86_64-linux";
    lib = nixpkgs.lib;

    # Whitelist of allowed unfree packages (used on the desktop host)
    unfreeNames = [
      "nvidia-x11" "nvidia-settings"
      "steam" "steam-unwrapped"
      "code" "vscode" "cursor" "microsoft-edge"
    ];
    allowUnfree = pkg: builtins.elem (lib.getName pkg) unfreeNames;
  in
  {
    # ── Desktop (physical machine) ──────────────────────────────
    nixosConfigurations.physshell = nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = { inherit allowUnfree inputs; };

      modules = [
        ./hosts/physshell/configuration.nix

        # System-wide allowUnfree predicate
        ({ ... }: { nixpkgs.config.allowUnfreePredicate = allowUnfree; })

        ./modules/maintenance.nix
        ({ ... }: { maintenance.enable = true; })

        home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bkp";

          home-manager.users.physshell = {
            imports = [
              agenix.homeManagerModules.default
              ./hosts/physshell/home.nix
              ./modules/hm-maintenance.nix
              ({ ... }: { hmMaintenance.enable = true; })
            ];
          };
        }
      ];
    };

    # ── WSL ─────────────────────────────────────────────────────
    nixosConfigurations.wsl = nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = { inherit inputs; };

      modules = [
        nixos-wsl.nixosModules.default
        ./hosts/wsl/configuration.nix

        home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bkp";

          home-manager.users.nixos = {
            imports = [
              ./hosts/wsl/home.nix
            ];
          };
        }
      ];
    };
  };
}
