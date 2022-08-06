{ pkgs ? import (import ./nix/sources.nix { }).test-stable { } }:
let
  # default.nix has one required argument—the used nixpkgs set.
  # Specific known-to-work versions can be found in nix/sources.json,
  # but in general I aim to support the latest release channel
  # (e.g. nixos-21.05) and nixos-unstable.
  nwt = import ./. { inherit pkgs; };

  # An example server configuration we’ll be using throughout.
  server = { config, lib, pkgs, ... }: {
    # In this example, we’ll have lighttpd serving a static page.
    services.lighttpd = {
      enable = true;
      document-root = pkgs.writeTextDir "index.html" ''
        <!doctype html>
        <html lang="en-GB">
          <head>
            <meta charset="utf-8">
            <title>Test page</title>
          </head>
          <body>
            <p>test</p>
          </body>
        </html>
      '';
    };

    networking.firewall.allowedTCPPorts = [ 80 ];
  };

in pkgs.linkFarmFromDrvs "nwt-examples" [
  # test runs a single test script on multiple browsers; for each
  # browser, the virtual network is re-created from scratch.
  (nwt.test {
    # Test name
    name = "nwt-a";

    # Virtual machines are specified in the nodes attribute.  A node
    # named ‘client’ running a SOCKS proxy used by the browser will be
    # automatically added, so the provided set should not contain it.
    nodes = { inherit server; };

    # Test script goes into a ‘script’ attribute.
    # It is a Python 3 script that has access to all NixOS test
    # globals (see
    # https://nixos.org/manual/nixos/stable/index.html#sec-nixos-tests)
    # for details, as well as an additional ‘driver’ global, which is
    # a Selenium web driver.
    script = ''
      from selenium.webdriver.common.by import By

      # Doing anything with the machine implicitly boots it if it is powered off.
      server.wait_for_open_port(80)

      driver.get("http://server")
      assert driver.find_element(By.CSS_SELECTOR, "body > p").text == 'test'
    '';
  })

  # It is also possible to run multiple test scripts in the same
  # environment.  Virtual machines will be created anew for each
  # script.
  (nwt.testMany {
    # Everything is mostly the same as in the previous case…
    name = "nwt-b";

    nodes = { inherit server; };

    # …except that there’s a scripts set instead of a single script.
    scripts = {
      title = ''
        server.wait_for_open_port(80)

        driver.get("http://server")
        assert driver.title == 'Test page'
      '';

      # Scripts can also live in files.
      body = ./example-body.py;
    };
  })

  # It is possible to specify the browsers you want tested.  It is
  # done identically for test and testMany.
  (nwt.test {
    name = "nwt-c";

    nodes = { inherit server; };

    # This is actually the default value.  Also available are
    # firefox-esr and chrome.
    browsers = b: [ b.firefox b.chromium ];

    script = ./example-body.py;
  })

  # You can also run a test in just a single browser; the advantage of
  # doing it this way instead of just passing a single-element list to
  # ‘browsers’ is that the result is the actual underlying ‘nixosTest’
  # derivation, including the all-important driverInteractive attribute.
  #
  # Do keep in mind that running the test interactively will attempt
  # to bind to port 1080 on your machine.
  (nwt.testSingleBrowser {
    name = "nwt-d";

    nodes = { inherit server; };

    browser = nwt.browsers.firefox-esr;

    script = ''
      server.wait_for_open_port(80)

      driver.get("http://server")
    '';
  })
]
