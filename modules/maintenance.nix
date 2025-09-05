# modules/maintenance.nix
{ lib, inputs, config, ... }:
with lib;
let
  cfg = config.maintenance;

  # Рекурсивно собираем все flake inputs, чтобы при желании "прибить" их как GC root
  collectFlakeInputs =
    input: [ input ] ++ lib.concatMap collectFlakeInputs (builtins.attrValues (input.inputs or {}));
in
{
  options.maintenance = {
    enable = mkEnableOption "Enable sensible Nix store maintenance defaults";

    # Инкрементальная оптимизация (hard-links) при добавлении путей
    autoOptimiseStore = mkOption {
      type = types.bool;
      default = true;
      description = "Set nix.settings.auto-optimise-store.";
    };

    # Периодическая оптимизация всего store
    optimise = {
      enable = mkEnableOption "Run nix-store --optimise on a schedule";
      dates = mkOption {
        type = types.listOf types.str;
        default = [ "04:15" ];
        description = "Systemd calendar times, e.g. [ \"daily\" ] or [ \"03:45\" ].";
      };
    };

    gc = {
      enable = mkEnableOption "Enable automatic GC";
      schedule = mkOption {
        type = types.str;
        default = "weekly";
        description = "Systemd OnCalendar for GC (e.g. \"daily\", \"weekly\", \"03:00\").";
      };
      deleteOlderThan = mkOption {
        type = types.str;
        default = "30d";
        description = "Passed to nix-collect-garbage --delete-older-than.";
      };
    };

    # minFree = mkOption {
    #   type = types.str;
    #   default = "2GiB";
    #   description = "nix.settings.min-free";
    # };
    # maxFree = mkOption {
    #   type = types.str;
    #   default = "6GiB";
    #   description = "nix.settings.max-free";
    # };

    pinFlakeInputs = mkOption {
      type = types.bool;
      default = true;
      description = "Keep all flake inputs as GC roots via system.extraDependencies.";
    };
  };

  config = mkIf cfg.enable {
    nix = {
      settings = {
        auto-optimise-store = cfg.autoOptimiseStore;
        #min-free = cfg.minFree;
        #max-free = cfg.maxFree;
      };

      optimise = mkIf cfg.optimise.enable {
        automatic = true;
        dates = cfg.optimise.dates;
      };

      gc = mkIf cfg.gc.enable {
        automatic = true;
        dates = cfg.gc.schedule;
        options = "--delete-older-than ${cfg.gc.deleteOlderThan}";
      };
    };

    system.extraDependencies = mkIf cfg.pinFlakeInputs (collectFlakeInputs inputs.self);
  };
}