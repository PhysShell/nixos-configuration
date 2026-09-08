# modules/wsl-disk-guard.nix
#
# nix.settings.min-free / max-free are the obvious answer to "stop filling the
# disk", and on a normal machine they are the right one.  Under WSL they are
# useless: they read free space from the filesystem, and the filesystem is a
# dynamically growing VHDX.  `df` inside the distro happily reports
#
#     /dev/sdc  1007G  182G  774G  20% /
#
# while the Windows volume holding ext4.vhdx has ~15 GiB left.  Nix never sees a
# shortage, keeps building, the VHDX grows until the host volume is full, and
# WSL then refuses to start at all (Wsl/Service/CreateInstance/E_FAIL) - a state
# repairable only from outside.
#
# So ask Windows for the number that is actually true, over WSL interop.
#
# The other half cannot be solved from in here at all: freeing space inside ext4
# never shrinks the VHDX, and Optimize-VHD needs the distro stopped plus
# Administrator.  Register a scheduled task once, elevated, and this guard can
# trigger it afterwards without a prompt - see compactTask.
#
# Structure follows nixos/modules/services/misc/nix-gc.nix and nix-optimise.nix:
# oneshot + startAt, restartIfChanged = false, RandomizedDelaySec, and idle
# scheduling so housekeeping never competes with real work.
{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.wslDiskGuard;

  # ExecCondition semantics: exit 0 runs the unit, 1-254 skips it silently.
  # Deciding "is there anything to do" here rather than inside the service keeps
  # a quiet hourly check out of the journal entirely.
  freeCheck = pkgs.writeShellScript "wsl-disk-guard-condition" ''
    set -u
    if [ ! -x ${escapeShellArg cfg.powershell} ]; then
      echo "wsl-disk-guard: interop binary ${cfg.powershell} not executable" >&2
      exit 1
    fi

    # Windows prints CRLF; strip it or the comparison below breaks.
    free_mib=$(${escapeShellArg cfg.powershell} -NoProfile -NonInteractive \
      -Command "[int]((Get-PSDrive ${cfg.hostDrive}).Free/1MB)" 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '\r')

    if ! ${pkgs.coreutils}/bin/expr "$free_mib" : "^[0-9][0-9]*$" > /dev/null 2>&1; then
      echo "wsl-disk-guard: could not read free space on ${cfg.hostDrive}: '$free_mib'" >&2
      exit 1
    fi

    if [ "$free_mib" -ge $(( ${toString cfg.freeThresholdGiB} * 1024 )) ]; then
      exit 1
    fi
    echo "wsl-disk-guard: ${cfg.hostDrive}: down to $free_mib MiB free"
  '';
in
{
  options.wslDiskGuard = {
    enable = mkEnableOption "Watch real host free space and collect garbage before WSL suffocates";

    hostDrive = mkOption {
      type = types.str;
      default = "C";
      example = "D";
      description = "Windows drive letter holding this distro's ext4.vhdx.";
    };

    freeThresholdGiB = mkOption {
      type = types.int;
      default = 20;
      description = ''
        Act when the host volume drops below this many GiB free.  Size it above
        your largest single build: an image build can add ~10 GiB before
        anything gets a chance to react.
      '';
    };

    deleteOlderThan = mkOption {
      type = types.str;
      default = "7d";
      description = "Passed to nix-collect-garbage --delete-older-than.";
    };

    dates = mkOption {
      type = types.listOf types.str;
      default = [ "hourly" ];
      description = "systemd OnCalendar expressions for the check.";
    };

    randomizedDelaySec = mkOption {
      type = types.singleLineStr;
      default = "5min";
      description = "Random delay before each run, as in nix.gc.randomizedDelaySec.";
    };

    compactTask = mkOption {
      type = types.str;
      default = "";
      example = "CompactWslDisk";
      description = ''
        Name of a Windows scheduled task that stops WSL and runs Optimize-VHD.
        Empty disables the call.  Register it once from an elevated shell;
        triggering it afterwards needs no elevation, which is what makes this
        usable unattended.

        The task terminates this distro, so it fires only when the machine looks
        idle, and at most once per compactMinIntervalHours.
      '';
    };

    compactMaxLoadHundredths = mkOption {
      type = types.int;
      default = 50;
      description = ''
        Skip compaction while the 1-minute load average is above this, given in
        hundredths (50 means 0.50).  Shell arithmetic has no floats, hence the
        unit.
      '';
    };

    compactMinIntervalHours = mkOption {
      type = types.int;
      default = 6;
      description = ''
        Never compact more often than this.  Without it, a host volume that
        stays below the threshold would stop the distro on every single run.
      '';
    };

    powershell = mkOption {
      type = types.str;
      default = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe";
      description = ''
        Path to the Windows PowerShell interop binary.  Spelled out because
        systemd units do not inherit the Windows PATH that appendWindowsPath
        gives interactive shells.
      '';
    };

    schtasks = mkOption {
      type = types.str;
      default = "/mnt/c/Windows/System32/schtasks.exe";
      description = "Path to schtasks.exe, used to trigger compactTask.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.wsl-disk-guard = {
      description = "Collect Nix garbage when the Windows host volume runs low";
      startAt = cfg.dates;
      # As in nix-gc: do not fire merely because the configuration changed.
      restartIfChanged = false;
      path = [ pkgs.nix pkgs.coreutils pkgs.gawk pkgs.procps ];

      serviceConfig = {
        Type = "oneshot";
        ExecCondition = freeCheck;
        # Same posture as nix-optimise: housekeeping yields to real work.
        Nice = 19;
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
      };

      script = ''
        set -euo pipefail

        # Compaction kills every process in the distro, so approximate "is this
        # machine busy" the way a person would: no build running, load settled.
        busy_reason() {
          if pgrep -f "nix-build|nix build|nixos-rebuild" > /dev/null 2>&1; then
            echo "a Nix build is running"
            return 0
          fi
          load_h=$(awk '{ printf "%d", $1 * 100 }' /proc/loadavg)
          if [ "$load_h" -gt ${toString cfg.compactMaxLoadHundredths} ]; then
            echo "load average $(cut -d ' ' -f1 /proc/loadavg)"
            return 0
          fi
          return 1
        }

        echo "wsl-disk-guard: collecting garbage"
        nix-collect-garbage --delete-older-than ${cfg.deleteOlderThan}

        ${optionalString (cfg.compactTask != "") ''
          # Freeing space inside ext4 does not shrink the VHDX; only the host can
          # do that, and only with the distro stopped -- which kills us too.
          stamp=/var/lib/wsl-disk-guard/last-compact
          mkdir -p "$(dirname "$stamp")"

          now=$(date +%s)
          last=0
          if [ -f "$stamp" ]; then last=$(cat "$stamp" 2>/dev/null || echo 0); fi
          if ! expr "$last" : "^[0-9][0-9]*$" > /dev/null 2>&1; then last=0; fi

          if [ $(( now - last )) -lt $(( ${toString cfg.compactMinIntervalHours} * 3600 )) ]; then
            echo "wsl-disk-guard: compacted $(( (now - last) / 60 )) min ago, skipping"
          elif reason=$(busy_reason); then
            echo "wsl-disk-guard: not compacting, $reason"
          else
            echo "$now" > "$stamp"
            echo "wsl-disk-guard: idle, triggering ${cfg.compactTask} (this stops WSL)"
            ${escapeShellArg cfg.schtasks} /run /tn ${escapeShellArg cfg.compactTask} || \
              echo "wsl-disk-guard: could not start ${cfg.compactTask}; is it registered?" >&2
          fi
        ''}
      '';
    };

    systemd.timers.wsl-disk-guard = {
      timerConfig = {
        RandomizedDelaySec = cfg.randomizedDelaySec;
        Persistent = true;
      };
    };
  };
}
