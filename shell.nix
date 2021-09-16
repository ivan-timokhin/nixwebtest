{ sources ? import ./nix/sources.nix }:
let pkgs = import sources.nixpkgs-dev { };
in pkgs.mkShell {
  packages = [
    pkgs.niv
    pkgs.nixfmt
    (pkgs.writeShellScriptBin "format-nix-all" ''
      exec ${pkgs.findutils}/bin/find . -path ./nix -prune -o -name '*.nix' -execdir ${pkgs.nixfmt}/bin/nixfmt {} +
    '')
  ];
}
