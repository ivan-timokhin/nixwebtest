nixwebtest is a thin wrapper around
[NixOS testing infrastructure](https://nixos.org/manual/nixos/stable/index.html#sec-nixos-tests)
and
[Selenium](https://www.selenium.dev/)
that aims to simplify low-budget end-to-end testing of web applications
deployed via NixOS modules.

You might *not* want to use `nixwebtest` because…

  * Only desktop Firefox and Chromium are supported.  No Edge, no
    mobile browsers, no Safari of any kind.
  * Each test involves spinning up a network of virtual machines,
    so a non-trivial suite can take quite a while, especially on CI
    that doesn’t support nested virtualisation.

You might nevertheless *consider* using `nixwebtest` if…

  * you need to test your application’s reaction to system-wide events
    and vice-versa,
  * you deploy your application via NixOS modules already, and want to
    test them alongside the application, or
  * the choice is between that or manual testing.

To expand on that last point: `nixwebtest` does not compete with a
proper Selenium Grid or what have you.  It competes with manually
poking around your side-project’s UI after every code change (and even
then a more conventional test script may serve you better if neither
of the first two points applies).

If you’re still interested, there are some examples in `examples.nix`
file in repository root.
