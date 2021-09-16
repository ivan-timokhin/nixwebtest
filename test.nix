{ sources ? import ./nix/sources.nix }:
let
  nixos = import sources.nixos { };
  nixos-unstable = import sources.nixos-unstable { };
  tests = pkgs:
    let runner = import ./. { inherit pkgs; };
    in runner.testMany {
      name = "webtest-nix-tests";
      browsers = b: [ b.firefox b.chromium ];
      scripts = {
        inline = ''
          print("Hello from an inline script")
          driver.fullscreen_window()
          client.screenshot("iscript")
        '';

        file = ./script.py;

        function = { nodes, ... }: ''
          client.screenshot("${nodes.client.config.test-support.displayManager.auto.user}")
        '';
      };
    };
in nixos.linkFarm "webtest-nix-multi-tests" [
  {
    name = "nixos";
    path = tests nixos;
  }
  {
    name = "nixos-unstable";
    path = tests nixos-unstable;
  }
]
