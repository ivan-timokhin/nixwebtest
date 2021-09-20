{ sources ? import ../nix/sources.nix }:
let
  test-pkgs = {
    nixos = import sources.nixos { };
    nixos-unstable = import sources.nixos-unstable { };
  };

  pkgs = test-pkgs.nixos;

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

        browsers = b: builtins.attrValues b;

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

      ocr = runner.test {
        name = "${name}-ocr";

        browsers = b: [ b.firefox ];

        nodes = { inherit webserver; };

        enableOCR = true;

        script = ''
          webserver.start()
          webserver.wait_for_open_port(80)

          driver.get("http://webserver")
          client.screenshot("${test-word}")
          client.wait_for_text("${test-word}")
          open('done', 'w')
        '';
      };
    };

  tests = builtins.mapAttrs testOn test-pkgs;

  run-all-tests = import ./linkfarm.nix pkgs "webtest-nix-selftests" tests;

in (pkgs.runCommand "webtest-nix-check-output" { } ''
  mkdir $out
  find -L ${run-all-tests} -printf '%y %P\n' | sort -k2 > $out/list
  diff $out/list ${./test-output}
'').overrideAttrs (oldAttrs: {
  passthru = {
    inherit tests;
    inherit run-all-tests;
  };
})
