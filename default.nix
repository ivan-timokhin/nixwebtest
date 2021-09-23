{ pkgs }:
let
  user = "alice";

  seleniumPort = 4444;

  pythonPkgs = pkgs.python3Packages;

  extraPythonPackages =
    pythonPkgs.requiredPythonModules [ pythonPkgs.selenium ];

  insertPythonPaths = pkgs.lib.strings.concatMapStringsSep "\n" (drv:
    if drv ? pythonModule then
      ''
        sys.path.insert(0, "${drv}/lib/${drv.pythonModule.libPrefix}/site-packages")''
    else
      "") extraPythonPackages;

  mkGeckodriver = p:
    p.geckodriver.overrideAttrs (oldAttrs: {
      patches = oldAttrs.patches ++ [ ./geckodriver_timeout.patch ];
    });

  browserSet = let
    mkBrowser = properties: {
      gui = properties // {
        name = "${properties.name}-gui";
        gui = true;
      };
      headless = properties // {
        name = "${properties.name}-headless";
        gui = false;
      };
    };
  in {
    firefox = mkBrowser {
      packages = p: [ p.firefox-unwrapped (mkGeckodriver p) ];
      seleniumModule = "firefox";
      name = "firefox";
    };

    firefox-esr = mkBrowser {
      packages = p: [ p.firefox-esr (mkGeckodriver p) ];
      seleniumModule = "firefox";
      name = "firefox-esr";
    };

    chromium = mkBrowser {
      packages = p: [ p.chromium ];
      seleniumModule = "chrome";
      name = "chromium";
    };

    chrome = mkBrowser {
      packages = p:
        [
          (p.runCommandLocal "chrome" { } ''
            mkdir -p $out/bin
            ln -s ${p.google-chrome}/bin/google-chrome-stable $out/bin/chrome
          '')
        ];
      seleniumModule = "chrome";
      name = "chrome";
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
            (modulesPath + "/../tests/common/user-account.nix")
            extraClientConfig
          ] ++ lib.optionals browser.gui [
            (modulesPath + "/../tests/common/x11.nix")
            { test-support.displayManager.auto.user = user; }
          ];

          virtualisation.memorySize = lib.mkOverride 200 1024;
          virtualisation.graphics = false;
          environment = {
            systemPackages = [ pkgs.selenium-server-standalone ]
              ++ browser.packages pkgs;

            variables = lib.mkIf browser.gui {
              "XAUTHORITY" = "/home/${user}/.Xauthority";
            };
          };

          networking.firewall.allowedTCPPorts = [ seleniumPort ];
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
          ${pkgs.lib.optionalString browser.gui "client.wait_for_x()"}

          port = ${toString seleniumPort}
          client.succeed("su - ${user} -c 'ulimit -c unlimited; selenium-server & disown'")
          client.wait_for_open_port(port)
          client.forward_port(port, port)

          options = Options()
          ${pkgs.lib.optionalString (!browser.gui) "options.headless = True"}
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
