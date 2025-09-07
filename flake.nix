{
  description = "Flake-based NixOS Configuration with home-manager";

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
  };

  outputs = inputs@{ self, nixpkgs, home-manager, agenix, ... }:
  let
    system = "x86_64-linux";
    lib = nixpkgs.lib;

    # Function to allow unfree packages
    unfreeNames = [
      "nvidia-x11" "nvidia-settings"
      "steam" "steam-unwrapped"
      "code" "vscode" "cursor" "microsoft-edge"
    ];

    allowUnfree = pkg: builtins.elem (lib.getName pkg) unfreeNames;

    hmPkgs = import nixpkgs {
      inherit system;
      config.allowUnfreePredicate = allowUnfree;
    };
  in
  {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = { inherit allowUnfree inputs; };

      modules = [
        ./hosts/physshell/configuration.nix

        # System-wide allowUnfree
        ({ ... }: { nixpkgs.config.allowUnfreePredicate = allowUnfree; })

        ./modules/maintenance.nix
        ({ ... }: { maintenance.enable = true; }) # Enable maintenance module with defaults

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

    # Upd: standalone home-manager configuration is kinda obscure now, I'll stick with NixOS module
    # for simplicity. Leaving this here for reference.
    # Being able to build HM config separately is useful for testing
    # and for using `home-manager switch` without rebuilding the whole system.
    # homeConfigurations.physshell = home-manager.lib.homeManagerConfiguration {
    #   pkgs = hmPkgs;
    #   modules = [
    #     agenix.homeManagerModules.default
    #     ./hosts/physshell/home.nix
    #     ./modules/hm-maintenance.nix
    #     ({ ... }: { hmMaintenance.enable = true; })
    #   ];
      # extraSpecialArgs = { inherit allowUnfree; }; # если нужно внутрь home.nix
    # };
  };
}