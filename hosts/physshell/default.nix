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

  
  # To be able to run devcontainer from WSL
  systemd.tmpfiles.rules = [
    # L+: force-create symlink (обновит, если уже есть)
    "L+  /usr/bin  -  -  -  -  /run/current-system/sw/bin"
  ];

  # Experimental and broken below...
  # Создать симлинки этих пакетов в «классических» /bin и /usr/bin
  #environment.pathsToLink = [ "/bin" "/usr/bin" ];

  #environment.extraOutputsToInstall = [ "bin" ];  # ← включает /bin/...
  #environment.sessionVariables.PATH = [ "/run/current-system/sw/bin" ] ;

  # Передаём PATH в non-login shell WSL
  #environment.shellInit = ''
  #  export PATH="/run/current-system/sw/bin:$PATH"
  #'';

  #environment.variables = {
    # lib.mkForce → «моя запись выигрывает», но при этом мы сохраняем
    # то, что уже было ($PATH), и прибавляем нужный каталог.
   # PATH = lib.mkForce "$PATH:/run/current-system/sw/bin";
  #};

  users.users.nixos.extraGroups = [ "docker" ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
