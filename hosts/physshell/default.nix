# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ lib, config, pkgs, ... }:

{
  wsl.defaultUser = "nixos";
  users.users.nixos = {
    isNormalUser = true;
    description = "PhysShell";
  };

  nixpkgs.config.allowUnfree = true;

  programs.nix-ld = {
    enable = true;
    package = pkgs.nix-ld-rs;
  };

  environment.systemPackages = with pkgs; [
    wget
    git
    htop
    docker
    coreutils-full
    util-linux
  ];

  virtualisation.docker = {
  # Consider disabling the system wide Docker daemon
  enable = false;

  rootless = {
    enable = true;
    setSocketVariable = true;
    # Optionally customize rootless Docker daemon settings
    daemon.settings = {
      dns = [ "1.1.1.1" "8.8.8.8" ];
      registry-mirrors = [ "https://mirror.gcr.io" ];
    };
  };
};

security.wrappers = {
  docker-rootlesskit = {
    owner = "root";
    group = "root";
    capabilities = "cap_net_bind_service+ep";
    source = "${pkgs.rootlesskit}/bin/rootlesskit";
  };
};

  # boot.kernel.sysctl = {
  #   "net.ipv4.ip_unprivileged_port_start" = 0;
  # };

  security.pki.certificateFiles = [
    ./localhost.pem
  ];
  
  # To be able to run devcontainer from WSL
  systemd.tmpfiles.rules = [
    # Should be fixed in https://github.com/nix-community/NixOS-WSL/issues/555 but cursor screws up without it
    "L+  /usr/bin  -  -  -  -  /run/current-system/sw/bin"
  ];

  users.users.nixos.extraGroups = [ "docker" ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
