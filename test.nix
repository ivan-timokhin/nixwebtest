let
  nixpkgs = fetchTarball
    "https://github.com/NixOS/nixpkgs/archive/e85f0175e3effe9ba191d66c09e8f1b7d6362d5e.tar.gz";
  pkgs = import nixpkgs { };
  runner = import ./. { inherit pkgs; };
  name = "tester";
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
]
