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

  testSingleBrowser = { name, browser, script, nodes }:
    assert !(pkgs.lib.hasAttr "client" nodes);
    pkgs.nixosTest ({
      inherit name;

      nodes = {
        client = { config, pkgs, lib, modulesPath, ... }: {
          imports = [
            sharedModule
            (modulesPath + "/../tests/common/x11.nix")
            (modulesPath + "/../tests/common/user-account.nix")
          ];

          test-support.displayManager.auto.user = user;

          virtualisation.memorySize = 1024;
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
          initialGlobals = globals()

          import shlex

          import sys

          import os

          ${insertPythonPaths}

          from selenium import webdriver
          from selenium.webdriver.${browser.seleniumModule}.options import Options

          def ru(cmd):
              return "su - ${user} -c " + shlex.quote(cmd)

          os.chdir(os.environ.get("out", os.getcwd()))

          start_all()
          client.wait_for_x()
          client.succeed(ru("ulimit -c unlimited; selenium-server & disown"))
          client.wait_for_open_port(${toString seleniumPort})

          options = Options()
          client.forward_port(${toString seleniumPort}, ${
            toString seleniumPort
          })
          with webdriver.Remote(options=options) as driver:
              driver.maximize_window()

              initialGlobals["driver"] = driver

              with open("${script''}") as f:
                  script = f.read()

              exec(script, initialGlobals)
        '';
    });

  test = { name, browsers, script, nodes }:
    pkgs.linkFarm name (map (browser: {
      name = browser.name;
      path = testSingleBrowser {
        name = "${name}-${browser.name}";
        inherit browser script nodes;
      };
    }) (browsers browserSet));

  testMany = { name, browsers, scripts, nodes }:
    pkgs.linkFarm name (map (scriptName: {
      name = scriptName;
      path = test {
        name = "${name}-${scriptName}";
        inherit browsers nodes;
        script = scripts.${scriptName};
      };
    }) (builtins.attrNames scripts));

in { inherit testSingleBrowser test testMany; }
