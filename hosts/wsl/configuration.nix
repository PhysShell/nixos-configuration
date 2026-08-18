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

  # Explicitly register the binfmt_misc handler for Windows .exe files.
  # Without it WSLInterop is registered racily at boot and running .exe
  # from Linux intermittently fails with "Exec format error".
  wsl.interop.register = true;

  # ── User ──────────────────────────────────────────────────────
  users.users.nixos = {
    isNormalUser = true;
    description = "PhysShell";
    shell = pkgs.zsh;
    extraGroups = [ "docker" ];
  };

  # devenv up передаёт nix настройку 'system'; она restricted, поэтому
  # без trusted-users падает с "Failed to get drvPath from shell derivation".
  nix.settings.trusted-users = [ "root" "nixos" ];

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
