# hosts/physshell/configuration.nix – Desktop (physical machine)
#
# Hardware-specific, desktop environment, sound, bluetooth, etc.
# Shared settings (nix, docker) come from common/*.nix via imports.

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/virtualisation.nix
    ../../common/core.nix
    ../../common/docker.nix
  ];

  # ── Boot ──────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl."vm.swappiness" = 10;

  # ── Network ───────────────────────────────────────────────────
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  networking.firewall.checkReversePath = false;

  # ── Locale / Timezone ─────────────────────────────────────────
  time.timeZone = "Asia/Almaty";
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

  # ── Display / GPU ─────────────────────────────────────────────
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = true;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Proton / legacy games
  };

  # ── Desktop Environment (Plasma 6 / X11) ─────────────────────
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.wayland.enable = false;

  services.xserver.xkb = {
    layout = "us,ru";
    variant = "";
    options = "grp:win_space_toggle";
  };

  # ── Printing ──────────────────────────────────────────────────
  services.printing.enable = true;

  # ── Sound (PipeWire) ──────────────────────────────────────────
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ── User ──────────────────────────────────────────────────────
  users.users.physshell = {
    isNormalUser = true;
    description = "PhysShell";
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel" "kvm" "adbusers" "docker" ];
  };

  nix.settings.trusted-users = [ "root" "physshell" ];

  # ── Steam (needs system-level firewall rules) ─────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = false;
  };

  # ── Certificates ──────────────────────────────────────────────
  security.pki.certificateFiles = [
    ./localhost.pem
  ];

  # ── Bluetooth ─────────────────────────────────────────────────
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  system.stateVersion = "25.05"; # Do not change after first install
}
