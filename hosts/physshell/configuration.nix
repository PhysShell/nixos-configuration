# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./modules/virtualisation.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # boot.loader.grub.efiSupport = true; 

  # Enable nVidia resume from suspend
  # boot.extraModprobeConfig = ''
  #  options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
  # '';

  # Kernel settings.
  boot.kernel.sysctl."vm.swappiness" = 10;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Enable networking
  networking.networkmanager.enable = true;
  networking.firewall.checkReversePath = false;
 # networking.firewall.allowedTCPPorts = [ 7070 ];


  # Set your time zone.
  time.timeZone = "Asia/Almaty";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ru_RU.UTF-8";
    LC_IDENTIFICATION = "ru_RU.UTF-8";
    LC_MEASUREMENT = "ru_RU.UTF-8";
    LC_MONETARY = "ru_RU.UTF-8";
    LC_NAME = "ru_RU.UTF-8";
    LC_NUMERIC = "ru_RU.UTF-8";
    LC_PAPER = "ru_RU.UTF-8";
    LC_TELEPHONE = "ru_RU.UTF-8";
    LC_TIME = "ru_RU.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable and configure proprietary Nvidia drivers.
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = true;
  };

  # Enable OpenGL
  hardware.graphics = {
    enable = true;
    enable32Bit = true;   # для Proton/старых игр
  };

  # Enable the GNOME Desktop Environment.
  # services.xserver.displayManager.gdm.enable = true;
  # services.xserver.desktopManager.gnome.enable = true;

  # Enable Plasma DE
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Wayland
  services.displayManager.sddm.wayland.enable = false;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us,ru";
    variant = "";
    options = "grp:win_space_toggle";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.physshell = {
    isNormalUser = true;
    description = "PhysShell";
    extraGroups = [ "networkmanager" "wheel" "kvm" "adbusers" "docker" ];
  };

  programs.zsh.enable = true;
  users.users.physshell.shell = pkgs.zsh;
  
  # Install Steam (cannot be in home.nix becuase of firewall settings)
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = false; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  # Moved to home.nix
  # programs.firefox.enable = true;
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  #environment.systemPackages = with pkgs; [
  #  pkgs.microsoft-edge
  #  pkgs.libGL
  #  pkgs.libglvnd
  #  pkgs.gnomeExtensions.brightness-control-using-ddcutil
  #  vscode.fhs
  #  code-cursor
  # pkgs.vscodium
  #  wget
  #  git
  #  htop
  #  ddcutil
  # vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  (lutris.override {
	#extraPkgs = pkgs: [
  #	  ];
	#extraLibraries = pkgs: [
	#  ];
  #  })
  #  wineWowPackages.stable
  #  winetricks
  #  transmission_4-gtk
  #];

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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
  system.stateVersion = "25.05"; # Did you read the comment?
}
