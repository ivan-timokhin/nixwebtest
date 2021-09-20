{ pkgs }:
let
  sharedModule = { virtualisation.graphics = false; };

  user = "alice";

  seleniumPort = 4444;

  pythonPkgs = pkgs.python3Packages;

  selenium = pythonPkgs.selenium;

  extraPythonPackages = pythonPkgs.requiredPythonModules [ selenium ];

  insertPythonPaths = pkgs.lib.strings.concatMapStringsSep "\n" (drv:
    if drv ? pythonModule then
      ''
        sys.path.insert(0, "${drv}/lib/${drv.pythonModule.libPrefix}/site-packages")''
    else
      "") extraPythonPackages;

  browserSet = {
    firefox = {
      packages = p: [ p.firefox-unwrapped p.geckodriver ];
      seleniumModule = "firefox";
      name = "firefox";
    };

    chromium = {
      packages = p: [ p.chromium ];
      seleniumModule = "chrome";
      name = "chromium";
    };
  };

  testSingleBrowser = { name, browser, script, nodes, extraClientConfig ? { }
    , enableOCR ? false }:
    assert !(pkgs.lib.hasAttr "client" nodes);
    pkgs.nixosTest ({
      inherit name enableOCR;

      nodes = {
        client = { config, pkgs, lib, modulesPath, ... }: {
          imports = [
            sharedModule
            (modulesPath + "/../tests/common/x11.nix")
            (modulesPath + "/../tests/common/user-account.nix")
            extraClientConfig
          ];

          test-support.displayManager.auto.user = user;

          virtualisation.memorySize = lib.mkOverride 200 1024;
          environment = {
            systemPackages = [ pkgs.selenium-server-standalone ]
              ++ browser.packages pkgs;

            variables = { "XAUTHORITY" = "/home/${user}/.Xauthority"; };
          };

          networking.firewall = { allowedTCPPorts = [ seleniumPort ]; };
        };
      } // nodes;

      testScript = r:
        let
          script' = if pkgs.lib.isFunction script then script r else script;
          script'' = if pkgs.lib.isString script' then
            pkgs.writeTextFile {
              name = "${name}-script";
              text = script';
            }
          else
            script';
        in ''
          scriptGlobals = globals()

          import sys
          import os

          ${insertPythonPaths}

          from selenium import webdriver
          from selenium.webdriver.${browser.seleniumModule}.options import Options

          if "out" in os.environ:
              os.chdir(os.environ["out"])

          client.start()
          client.wait_for_x()

          port = ${toString seleniumPort}
          client.succeed("su - ${user} -c 'ulimit -c unlimited; selenium-server & disown'")
          client.wait_for_open_port(port)
          client.forward_port(port, port)

          options = Options()
          with webdriver.Remote(options=options) as driver:
              driver.maximize_window()

              scriptGlobals["driver"] = driver

              with open("${script''}") as f:
                  script = f.read()

              # This is not strictly necessary, but associates a file
              # name with the script text for slightly friendlier
              # error messages
              script = compile(script, "${script''}", 'exec')

              exec(script, scriptGlobals)
        '';
    });

  test = { name, browsers, script, nodes, extraClientConfig ? { }
    , enableOCR ? false }:
    pkgs.linkFarm name (map (browser: {
      name = browser.name;
      path = testSingleBrowser {
        name = "${name}-${browser.name}";
        inherit browser script nodes extraClientConfig enableOCR;
      };
    }) (browsers browserSet));

  testMany = { name, browsers, scripts, nodes, extraClientConfig ? { }
    , enableOCR ? false }:
    pkgs.linkFarm name (map (scriptName: {
      name = scriptName;
      path = test {
        name = "${name}-${scriptName}";
        inherit browsers nodes extraClientConfig enableOCR;
        script = scripts.${scriptName};
      };
    }) (builtins.attrNames scripts));

in { inherit testSingleBrowser test testMany; }
