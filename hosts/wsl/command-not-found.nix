# hosts/wsl/command-not-found.nix – run missing commands through nix-shell -p
#
# The stock handler only needs programs.sqlite, which the flake's GitHub
# nixpkgs lacks.  The channel tarball of the same revision ships it, so take
# just that file from there.  Not a flake input on purpose: maintenance.nix
# pins every flake input as a GC root, which would drag it into physshell.
{ lib, pkgs, inputs, ... }:

let
  # Channel release names end in the short nixpkgs revision.  Bump this (and
  # the hash) after `nix flake update nixpkgs`; the assertion below insists.
  release = "nixos-26.11pre1027867.d407951447dc";

  channel = pkgs.fetchurl {
    url = "https://releases.nixos.org/nixos/unstable/${release}/nixexprs.tar.xz";
    hash = "sha256-1X8LnuZR0QNpL18M9yjduwVfboQR9/p5XpKIwE2WK4o=";
  };

  programsDb = pkgs.runCommand "programs.sqlite" { } ''
    tar -xJf ${channel} --wildcards --strip-components=1 '*/programs.sqlite'
    mv programs.sqlite $out
  '';

  nixpkgsShortRev = builtins.substring 0 12 inputs.nixpkgs.rev;

  # Both prompts loop on `<STDIN>` without checking for EOF, so Ctrl-D (or a
  # closed stdin) makes them spin forever, re-printing the prompt.  Treat EOF
  # as "no": exit 127 as if auto-run were off.  --replace-fail breaks the
  # build once upstream changes these lines; drop the patch if they fixed it.
  patchedScript = pkgs.runCommand "command-not-found.pl" { } ''
    cp ${pkgs.path}/nixos/modules/programs/command-not-found/command-not-found.pl $out
    substituteInPlace $out \
      --replace-fail 'chomp(my $confirm = <STDIN>);' \
        'my $confirm = <STDIN>; exit 127 unless defined $confirm; chomp $confirm;' \
      --replace-fail '$choice = <STDIN> + 0;' \
        'my $line = <STDIN>; exit 127 unless defined $line; $choice = $line + 0;'
  '';

  # Same as the module's own `commandNotFound`, which it does not expose.
  commandNotFound = pkgs.replaceVarsWith {
    name = "command-not-found";
    dir = "bin";
    src = patchedScript;
    isExecutable = true;
    replacements = {
      dbPath = programsDb;
      perl = pkgs.perl.withPackages (p: [
        p.DBDSQLite
        p.StringShellQuote
      ]);
    };
  };
  cnf = "${commandNotFound}/bin/command-not-found";
in
{
  assertions = [
    {
      assertion = lib.hasSuffix nixpkgsShortRev release;
      message = ''
        command-not-found: programs.sqlite comes from channel release
        ${release}, but nixpkgs is locked at ${inputs.nixpkgs.rev}.
        Set `release` (and its hash) in hosts/wsl/command-not-found.nix to
        the channel release of that revision.
      '';
    }
  ];

  programs.command-not-found = {
    enable = true;
    dbPath = programsDb;
  };

  # Ask before running the package (several matches: pick one by number).
  environment.variables = {
    NIX_AUTO_RUN = "1";
    NIX_AUTO_RUN_INTERACTIVE = "1";
  };

  # The module still puts its unpatched copy on PATH; shadow it.
  environment.systemPackages = [ (lib.hiPrio commandNotFound) ];

  # Replace the module's handlers (defined earlier in the same files) with
  # ones that call the patched script.  Without a terminal on stdin (pipes,
  # </dev/null, scripts) nobody can answer the prompt, so only print the hint.
  programs.zsh.interactiveShellInit = lib.mkAfter ''
    command_not_found_handler() {
      if [[ -t 0 ]]; then
        '${cnf}' "$@"
      else
        NIX_AUTO_RUN= '${cnf}' "$@"
      fi
    }
  '';

  programs.bash.interactiveShellInit = lib.mkAfter ''
    command_not_found_handle() {
      if [[ -t 0 ]]; then
        '${cnf}' "$@"
      else
        NIX_AUTO_RUN= '${cnf}' "$@"
      fi
    }
  '';
}
