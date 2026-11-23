# WSL memory

Why `vmmemWSL` grows, what limits it, and how to check that a change helped.
Researched 2026-11-24 (WSL 3.0.5, kernel 6.18.58.1, NixOS 26.11).

## Why the VM holds so much

Inside the VM most of the memory after a working day is page cache: Nix store
paths, build outputs, test data. Linux keeps it until it needs the RAM, and
Windows sees it as used by `vmmemWSL`. After `wsl --shutdown` the guest itself
uses well under 1 GB.

WSL gives cached pages back with `autoMemoryReclaim` (`[experimental]` in
`.wslconfig`): `dropCache` (the default in WSL 3.0.x) drops the cache at once
after about five minutes of low CPU activity, `gradual` releases it over about
half an hour. Long-running services keep the VM from looking idle, so reclaim
may not run during a busy day.

`gradual` once broke Docker (WSL 2.0.0, microsoft/WSL#10497); WSL 2.0.1 fixed
it by mounting cgroup v2 at `/sys/fs/cgroup`. A later rootless-Docker
regression (WSL 2.9, microsoft/WSL#41492) is reported fixed in 3.0.x. Either
mode is fine to try; `docker run --rm hello-world` after the switch is the test.

Manual drop after heavy work, from Windows:

```powershell
wsl -u root sh -c "sync; echo 3 > /proc/sys/vm/drop_caches"
```

## Limits: `.wslconfig`

`%UserProfile%\.wslconfig` (Windows side; applied only after `wsl --shutdown`,
which stops everything in the VM):

```ini
[wsl2]
networkingMode=mirrored
nestedVirtualization=true
processors=8
memory=8GB
swap=8GB
swapFile=C:\\wsl\\swap.vhdx

[experimental]
autoMemoryReclaim=dropCache
```

With `swap=0` the guest OOM killer kills processes the moment the cap is hit.
With a swap file the VM slows down instead. If builds page heavily, raise
`memory` to 10GB before raising anything else.

## Limits: this flake (`hosts/wsl/memory.nix`)

- `nix.settings.max-jobs = 2`, `cores = 4`: `auto`/`0` meant up to 8 builds of
  8 threads each, the main source of memory peaks.
- `services.earlyoom`: kills the heaviest build process when free RAM is below
  5 % and free swap below 10 %, preferring compilers and test runners, never
  nix-daemon or dockerd.
- Rootless Docker no longer starts with the session:
  `systemctl --user start docker` when needed.

## Optional: zram

zram keeps a compressed swap device in RAM and is used before the disk swap
file when it has the higher priority. On WSL the gain is smaller than on bare
metal because Windows already compresses memory.

The Microsoft kernel builds zram as a module (`CONFIG_ZRAM=m`), has no zswap,
and does not build the zstd backend that NixOS uses by default. Check first:

```bash
sudo modprobe zram && echo ok
modinfo zram | head -3
```

If that works, uncomment the `zramSwap` block in `hosts/wsl/memory.nix`
(`algorithm = "lzo-rle"`, `memoryPercent = 25`, `priority = 100`), rebuild,
and check with `zramctl` and `swapon --show`.

## Measuring

Same kind of working day before and after; readings at the peak and ten
minutes after the last job.

- Windows: `(Get-Process vmmemWSL).WorkingSet64 / 1GB`, Task Manager
  Memory > Available and Committed.
- Linux: `free -h` (used vs buff/cache), `vmstat 5` (`si`/`so` = paging),
  `cat /proc/pressure/memory`, `journalctl -u earlyoom`.
