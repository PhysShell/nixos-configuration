# hosts/wsl/configuration.nix – NixOS-on-WSL system configuration
{ lib, config, pkgs, ... }:

{
  imports = [
    ../../common/core.nix
    ../../common/docker.nix
  ];

  # ── WSL-specific ──────────────────────────────────────────────
  wsl.enable = true;
  wsl.defaultUser = "nixos";

  # ── User ──────────────────────────────────────────────────────
  users.users.nixos = {
    isNormalUser = true;
    description = "PhysShell";
    shell = pkgs.zsh;
    extraGroups = [ "docker" ];
  };

  # WSL is less restrictive about unfree
  nixpkgs.config.allowUnfree = true;

  # Allow running unpatched dynamic binaries (VS Code server, etc.)
  programs.nix-ld.enable = true;

  # Extra system packages beyond what home-manager provides
  environment.systemPackages = with pkgs; [
    docker
    coreutils-full
    util-linux
  ];

  # Dev certificate
  security.pki.certificateFiles = [
    ./localhost.pem
  ];

  system.stateVersion = "24.11"; # Do not change after first install
}
