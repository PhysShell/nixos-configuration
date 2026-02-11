# hosts/physshell/home.nix – Desktop-specific Home Manager additions
#
# Shared tools come from home/base.nix (shell, dev CLI).
# GUI / desktop packages come from home/desktop.nix.
# This file adds only physshell-specific bits: user identity, agenix, SSH keys.
{ config, pkgs, lib, ... }:

{
  imports = [
    ../../home/base.nix
    ../../home/desktop.nix
  ];

  # ── Identity ──────────────────────────────────────────────────
  home.username = "physshell";
  home.homeDirectory = "/home/physshell";

  # ── Agenix secrets ───────────────────────────────────────────
  age.identityPaths = [ "/home/physshell/.ssh/agenix_id_ed25519" ];

  age.secrets.private_ssh_config = {
    file = ./secrets/private-ssh-config.age;
    mode = "600";
  };

  # ── SSH ───────────────────────────────────────────────────────
  services.ssh-agent.enable = true;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ config.age.secrets.private_ssh_config.path ];
    matchBlocks = {
      "*" = {
        identitiesOnly = true;
        addKeysToAgent = "yes";
      };
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = [ "~/.ssh/id_ed25519_github_home_pc" ];
        identitiesOnly = true;
        addKeysToAgent = "yes";
      };
    };
  };

  home.stateVersion = "25.05";
}
