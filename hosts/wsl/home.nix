# hosts/wsl/home.nix – WSL-specific Home Manager additions
#
# All the shared tools (zsh, starship, fzf, git…) come from home/base.nix.
# Put only WSL-specific tweaks here.
{ config, pkgs, lib, ... }:

{
  imports = [
    ../../home/base.nix
  ];

  home.username = "nixos";
  home.homeDirectory = "/home/nixos";

  services.ssh-agent.enable = true;

  programs.ssh = {
    settings = {
      "github.com" = {
        HostName = "github.com";
        User = "git";
        IdentityFile = [ "~/.ssh/id_ed25519_github_wsl" ];
        IdentitiesOnly = true;
        AddKeysToAgent = "yes";
      };
    };
  };

  home.stateVersion = "24.11";
}
