{ sources ? import ../nix/sources.nix }:
let
  test-pkgs = {
    stable = import sources.test-stable { };
    unstable = import sources.test-unstable { };
  };

  pkgs = import sources.nixpkgs-dev { };

  test-word = "easily";

  test-page = pkgs.writeTextDir "index.html" ''
    <!DOCTYPE html>
    <html lang="en-GB">
      <head>
        <meta charset="utf-8">
        <title>Test page</title>
        <style>
          body {
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: center;
              min-height: 100vh;
              min-width: 100vw;
              position: fixed;
          }

          body > p {
              font-size: 60px;
              font-family: monospace;
          }
        </style>
      </head>
      <body>
        <p>${test-word}</p>
      </body>
    </html>
  '';

  test-module = { lib, ... }: {
    options = {
      test-word = lib.mkOption {
        type = lib.types.str;
        description = "Text inserted into config for test purposes";
      };
    };

    config = { inherit test-word; };
  };

  webserver = { config, lib, pkgs, ... }: {
    imports = [ test-module ];

    services.lighttpd = {
      enable = true;
      document-root = "${test-page}";
    };

    networking.firewall.allowedTCPPorts = [ 80 ];
  };

  testOn = name: pkgs:
    let runner = import ../. { inherit pkgs; };
    in {
      script-types = runner.testMany {
        name = "${name}-scripts";
        browsers = b: [ b.chromium ];

        nodes = { inherit webserver; };

        scripts = {
          inline = "open('done', 'w')";

          path = ./css-check.py;

          function-inline = { nodes, ... }:
            assert nodes.webserver.config.test-word == test-word;
            "open('done', 'w')";

          function-path = { nodes, ... }:
            assert nodes.webserver.config.test-word == test-word;
            ./css-check.py;
        };
      };

      browsers = runner.test {
        name = "${name}-browsers";

        browsers = builtins.attrValues;

        nodes = { inherit webserver; };

        script = ''
          webserver.start()
          webserver.wait_for_open_port(80)

          driver.get("http://webserver")
          p = driver.find_element_by_css_selector("body > p")
          assert p.text == "${test-word}"
          open("done", "w")
        '';
      };

      screenshots = runner.testMany {
        name = "${name}-screenshots";

        browsers = b: [ b.firefox ];

        nodes = { };

        scripts = {
          selenium = "driver.save_screenshot('screen.png')";
          nixos = "client.screenshot('screen')";
        };
      };

      client-config = runner.test {
        name = "${name}-cc";

        browsers = b: [ b.firefox ];

        nodes = { };

        extraClientConfig = test-module;

        script = { nodes, ... }:
          assert nodes.client.config.test-word == test-word;
          "open('done', 'w')";
      };

      client-memory = runner.test {
        name = "${name}-cm";

        browsers = b: [ b.firefox ];

        nodes = { };

        extraClientConfig = { virtualisation.memorySize = 768; };

        script = { nodes, ... }:
          assert nodes.client.config.virtualisation.memorySize == 768;
          "open('done', 'w')";
      };

      single = runner.testSingleBrowser {
        name = "${name}-single";

        browser = runner.browsers.firefox-esr;

        nodes = { };

        script = ''
          open(driver.capabilities['browserName'], 'w')
        '';
      };

      defaults = runner.test {
        name = "${name}-defaults";

        nodes = { };

        script = ''
          open(driver.capabilities['browserName'], 'w')
        '';
      };

      examples = import ../examples.nix { inherit pkgs; };
    };

  tests = builtins.mapAttrs testOn test-pkgs;

  run-all-tests = import ./linkfarm.nix pkgs "nixwebtest-selftests" tests;

in (pkgs.runCommand "nixwebtest-check-output" { } ''
  mkdir $out
  find -L ${run-all-tests} -printf '%y %P\n' | sort -k2 > $out/list
  diff $out/list ${./test-output}
'').overrideAttrs (oldAttrs: {
  passthru = {
    inherit tests;
    inherit run-all-tests;
  };
})
