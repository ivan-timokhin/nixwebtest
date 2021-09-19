{ sources ? import ./nix/sources.nix }:
let pkgs = import sources.nixpkgs-dev { };
in pkgs.mkShell {
  packages = [
    pkgs.niv
    pkgs.nixfmt
    (pkgs.writeShellScriptBin "format-nix-all" ''
      exec ${pkgs.findutils}/bin/find . -path ./nix -prune -o -name '*.nix' -execdir ${pkgs.nixfmt}/bin/nixfmt {} +
    '')
    (pkgs.writeShellScriptBin "update-test-listing" ''
      ${pkgs.findutils}/bin/find -L $(nix-build tests --no-out-link -A run-all-tests) -printf '%y %P\n'\
       | LC_ALL=C ${pkgs.coreutils}/bin/sort -k2 > tests/test-output
    '')
  ];
}
