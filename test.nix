{ sources ? import ./nix/sources.nix }:
let
  nixos = import sources.nixos { };
  nixos-unstable = import sources.nixos-unstable { };
  name = "tester";
  tests = { pkgs }:
    let runner = import ./. { inherit pkgs; };
    in pkgs.linkFarm "webtest-nix-tests" [
      {
        name = "${name}-inline-script";
        path = runner {
          name = "${name}-inline-script";
          browsers = b: [ b.firefox b.chromium ];

          script = ''
            print("Hello from an inline script")
            driver.fullscreen_window()
            client.screenshot("iscript")
          '';
        };
      }
      {
        name = "${name}-file-script";
        path = runner {
          name = "${name}-file-script";
          browsers = b: [ b.firefox b.chromium ];

          script = ./script.py;
        };
      }
      {
        name = "${name}-fun-script";
        path = runner {
          name = "${name}-fun-script";
          browsers = b: [ b.firefox b.chromium ];

          script = { nodes, ... }: ''
            client.screenshot("${nodes.client.config.test-support.displayManager.auto.user}")
          '';
        };
      }
    ];
in nixos.linkFarm "webtest-nix-multi-tests" [
  {
    name = "nixos";
    path = tests { pkgs = nixos; };
  }
  {
    name = "nixos-unstable";
    path = tests { pkgs = nixos-unstable; };
  }
]
