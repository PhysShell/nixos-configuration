# home/desktop.nix – GUI / desktop-only additions (physshell, not WSL)
#
# Fonts, graphical editors, browsers, gaming, vulnix scanner.
{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # Editors / browsers
    vscode.fhs
    code-cursor
    microsoft-edge

    # Gaming
    (lutris.override {
      extraPkgs = pkgs: [];
      extraLibraries = pkgs: [];
    })
    wineWowPackages.stable
    winetricks

    transmission_4-gtk

    # Security scanner
    vulnix

    # Nerd Fonts (set JetBrainsMono in your Konsole profile)
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code

    # Middle-mouse-click emulation via keyboard
    xdotool
    (pkgs.writeShellScriptBin "mouse-middle-click" ''
      ${pkgs.xdotool}/bin/xdotool click 2
    '')
  ];

  programs.firefox.enable = true;

  # User-level fontconfig
  fonts.fontconfig.enable = true;

  # ── Vulnix daily scan ────────────────────────────────────────
  systemd.user.services.vulnix-scan = {
    Unit.Description = "Daily vulnix scan (user)";
    Service = {
      Type = "oneshot";
      ExecStart =
        let out = "${config.xdg.stateHome}/vulnix";
        in ''
          ${pkgs.coreutils}/bin/mkdir -p '${out}'
          ${pkgs.vulnix}/bin/vulnix --system --json > '${out}/'$(date +%F).json
        '';
    };
  };

  systemd.user.timers.vulnix-scan = {
    Unit.Description = "Timer: vulnix scan daily";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "vulnix-scan.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
