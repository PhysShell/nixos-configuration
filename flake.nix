{
  description = "Flake-based NixOS Configuration for WSL 2";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
  };

  outputs = { self, nixpkgs, nixos-wsl, ... }:
  {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
	nixos-wsl.nixosModules.default
	{
	   system.stateVersion = "24.11";
           wsl.enable = true;
	}
        ./hosts/physshell
      ];
    };
  };
}

