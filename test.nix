let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/e85f0175e3effe9ba191d66c09e8f1b7d6362d5e.tar.gz";
  pkgs = import nixpkgs {};
  runner = import ./. { inherit pkgs; };
in
{
  firefox = runner { browser = b: b.firefox; };
  chromium = runner { browser = b: b.chromium; };
}
