{
  description = "Example Flake-based NixOS Configuration";


  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    #dzgui-nix.url = "github:PhysShell/dzgui-nix";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, dzgui-nix, ... }:
  {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/physshell/default.nix
        ./hosts/physshell/modules/wireguard.nix
        #dzgui-nix.nixosModules.default 
        #{ programs.dzgui.enable = true; }
      ];
    };
  };
}

