{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.hmMaintenance;
in
{
  options.hmMaintenance = {
    enable = mkEnableOption "Enable daily Home Manager generations cleanup";
    expireOlderThan = mkOption {
      type = types.str;
      default = "30 days";
      description = "Argument for `home-manager expire-generations`.";
    };
  };

  config = mkIf cfg.enable {
    programs.home-manager.enable = true;

    systemd.user.services.home-manager-expire = {
      Unit.Description = "Expire old Home Manager generations";
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe (pkgs.writeShellScriptBin "hm-expire" ''
          ${lib.getExe pkgs.home-manager} expire-generations "${cfg.expireOlderThan}"
        '');
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.timers.home-manager-expire = {
      Unit.Description = "Timer: expire old Home Manager generations";
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}