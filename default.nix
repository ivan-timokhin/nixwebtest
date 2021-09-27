{ pkgs }:
let
  socksPort = 1080;

  pythonPkgs = pkgs.python3Packages;

  extraPythonPackages =
    pythonPkgs.requiredPythonModules [ pythonPkgs.selenium ];

  insertPythonPaths = pkgs.lib.strings.concatMapStringsSep "\n" (drv:
    if drv ? pythonModule then
      ''
        sys.path.insert(0, "${drv}/lib/${drv.pythonModule.libPrefix}/site-packages")''
    else
      "") extraPythonPackages;

  browserSet = let
    chromeScript = pkgs: binary:
      pkgs.writeTextFile {
        name = "chrome-script";
        text = ''
          from selenium.webdriver.chrome.options import Options
          from selenium.webdriver.chrome.webdriver import WebDriver

          # See https://github.com/NixOS/nixpkgs/issues/136207
          # (or https://bugs.chromium.org/p/chromium/issues/detail?id=1245258
          # I guess, but that gives me ‘Permission denied’)
          os.environ["FONTCONFIG_FILE"] = "${
            pkgs.makeFontsConf { fontDirectories = [ ]; }
          }"

          # See https://github.com/NixOS/nixpkgs/issues/139547
          os.environ["LD_LIBRARY_PATH"] = "${pkgs.dbus.lib}/lib"

          def mkDriver(proxy):
              options = Options()
              options.headless = True
              options.set_capability('proxy', proxy)
              options.binary_location = '${binary}'
              options.set_capability('args', ['--no-sandbox'])
              options.set_capability('acceptSslCerts', True)

              return WebDriver(executable_path='${pkgs.chromedriver}/bin/chromedriver', options=options)
        '';
      };

    firefoxScript = pkgs: binary:
      pkgs.writeTextFile {
        name = "firefox-script";
        text = ''
          from selenium.webdriver.firefox.options import Options
          from selenium.webdriver.firefox.webdriver import WebDriver
          from selenium.webdriver.firefox.firefox_profile import FirefoxProfile

          os.environ["HOME"] = os.getcwd()

          def mkDriver(proxy):
              options = Options()
              options.headless = True
              options.set_capability('proxy', proxy)
              options.binary_location = '${binary}'

              profile = FirefoxProfile()
              profile.set_preference("network.proxy.socks_remote_dns", True)

              options.profile = profile

              return WebDriver(executable_path='${pkgs.geckodriver}/bin/geckodriver', options=options)
        '';
      };
  in {
    firefox = {
      name = "firefox";
      script = pkgs: firefoxScript pkgs "${pkgs.firefox}/bin/firefox";
    };

    firefox-esr = {
      name = "firefox-esr";
      script = pkgs: firefoxScript pkgs "${pkgs.firefox-esr}/bin/firefox";
    };

    chromium = {
      name = "chromium";
      script = pkgs: chromeScript pkgs "${pkgs.chromium}/bin/chromium";
    };

    chrome = {
      name = "chrome";
      script = pkgs:
        chromeScript pkgs "${pkgs.google-chrome}/bin/google-chrome-stable";
    };
  };

  defaultBrowsers = b: [ b.firefox b.chromium ];

  testSingleBrowser = { name, browser, script, nodes, extraClientConfig ? { }
    , enableOCR ? false }:
    assert !(pkgs.lib.hasAttr "client" nodes);
    pkgs.nixosTest ({
      inherit name enableOCR;

      nodes = {
        client = { config, pkgs, lib, modulesPath, ... }: {
          imports = [ extraClientConfig ];

          networking.firewall.allowedTCPPorts = [ socksPort ];

          services.dante.enable = true;
          services.dante.config = ''
            internal: 0.0.0.0 port = ${toString socksPort}
            external: eth1
            clientmethod: none
            socksmethod: none
            client pass {
                  from: 0.0.0.0/0 to: 0.0.0.0/0
                  log: error connect disconnect
            }
            socks pass {
                  from: 0.0.0.0/0 to: 0.0.0.0/0
                  command: bind connect udpassociate bindreply udpreply
                  log: error connect disconnect iooperation
            }
          '';
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

          client.start()
          client.wait_for_open_port(${toString socksPort})

          client.forward_port(${toString socksPort}, ${toString socksPort})

          with open('${browser.script pkgs}') as f:
              bscript = f.read()

          bscriptGlobals = globals()
          exec(bscript, bscriptGlobals)

          if "out" in os.environ:
              os.chdir(os.environ["out"])

          proxy = {
              'proxyType': 'MANUAL',
              'socksProxy': '127.0.0.1:${toString socksPort}',
              'socksVersion': 5
          }

          with bscriptGlobals['mkDriver'](proxy = proxy) as driver:
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

  test = { name, browsers ? defaultBrowsers, script, nodes
    , extraClientConfig ? { }, enableOCR ? false }:
    pkgs.linkFarm name (map (browser: {
      name = browser.name;
      path = testSingleBrowser {
        name = "${name}-${browser.name}";
        inherit browser script nodes extraClientConfig enableOCR;
      };
    }) (browsers browserSet));

  testMany = { name, browsers ? defaultBrowsers, scripts, nodes
    , extraClientConfig ? { }, enableOCR ? false }:
    pkgs.linkFarm name (map (scriptName: {
      name = scriptName;
      path = test {
        name = "${name}-${scriptName}";
        inherit browsers nodes extraClientConfig enableOCR;
        script = scripts.${scriptName};
      };
    }) (builtins.attrNames scripts));

in {
  inherit testSingleBrowser test testMany;
  browsers = browserSet;
  self-signed-cert = import ./ssl.nix pkgs;
}
