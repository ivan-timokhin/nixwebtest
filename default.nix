{ pkgs }:
let
  sharedModule = {
    virtualisation.graphics = false;
  };

  user = "alice";
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
        ];

        variables = {
          "XAUTHORITY" = "/home/${user}/.Xauthority";
        };
      };
    };
  };

  testScript = ''
    import shlex

    def ru(cmd):
        return "su - ${user} -c " + shlex.quote(cmd)

    start_all()
    print("Start")
    client.wait_for_x()
    client.screenshot("initial")
    client.succeed(ru("ulimit -c unlimited; chromium & disown"))
    client.wait_for_window("Chromium")
    client.sleep(10)
    client.screenshot("chromium")
  '';
})
