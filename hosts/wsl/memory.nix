# hosts/wsl/memory.nix – keep the WSL VM from starving Windows
#
# The VM size is capped and given a disk swap file in %UserProfile%\.wslconfig
# (see docs/wsl-memory.md); this module keeps peaks inside that cap and kills a
# runaway build before the guest OOM killer picks a random victim.
{ lib, ... }:

{
  # max-jobs = auto and cores = 0 allow up to 8 builds x 8 threads each.
  nix.settings = {
    max-jobs = 2;
    cores = 4;
  };

  # Acts only when both free RAM and free swap drop below the thresholds.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    extraArgs = [
      "--prefer" "(rustc|cc1plus|node|python3)"
      "--avoid" "(nix-daemon|dockerd|systemd)"
    ];
  };

  # Rootless Docker starts on demand: systemctl --user start docker
  systemd.user.services.docker.wantedBy = lib.mkForce [ ];

  # Compressed swap in RAM, optional; read docs/wsl-memory.md first (the WSL
  # kernel ships zram as a module and has no zstd backend for it).
  # zramSwap = {
  #   enable = true;
  #   memoryPercent = 25;
  #   algorithm = "lzo-rle";
  #   priority = 100;
  # };
}
