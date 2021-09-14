{ pkgs }:
let
  sharedModule = {
    virtualisation.graphics = false;
  };

  user = "alice";

  seleniumPort = 4444;

  pythonPkgs = pkgs.python3Packages;

  selenium = pythonPkgs.selenium;

  extraPythonPackages = pythonPkgs.requiredPythonModules [ selenium ];

  insertPythonPaths = pkgs.lib.strings.concatMapStringsSep "\n" (
    drv:
    if drv ? pythonModule
    then ''sys.path.insert(0, "${drv}/lib/${drv.pythonModule.libPrefix}/site-packages")''
    else ""
  ) extraPythonPackages;
in
pkgs.nixosTest ({
  nodes = {
    client = { config, pkgs, lib, modulesPath, ... }: {
      imports = [
        sharedModule
        (modulesPath + "/../tests/common/x11.nix")
        (modulesPath + "/../tests/common/user-account.nix")
      ];

      test-support.displayManager.auto.user = user;

      environment = {
        systemPackages = [
          pkgs.chromium
          pkgs.selenium-server-standalone
        ];

        variables = {
          "XAUTHORITY" = "/home/${user}/.Xauthority";
        };
      };

      networking.firewall = {
        allowedTCPPorts = [ seleniumPort ];
      };
    };
  };

  testScript = ''
    import shlex

    import sys

    ${insertPythonPaths}

    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options

    def ru(cmd):
        return "su - ${user} -c " + shlex.quote(cmd)

    start_all()
    client.wait_for_x()
    client.screenshot("initial")
    client.succeed(ru("ulimit -c unlimited; selenium-server & disown"))
    client.wait_for_open_port(${toString seleniumPort})
    client.screenshot("after")

    options = Options()
    client.forward_port(${toString seleniumPort}, ${toString seleniumPort})
    with webdriver.Remote(options=options) as driver:
        driver.maximize_window()
        client.screenshot("maximized")
  '';
})
