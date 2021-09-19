pkgs:
let
  linkfarm = name: set:
    if pkgs.lib.isDerivation set then
      set
    else
      pkgs.linkFarm name (map (attr: {
        name = attr;
        path = linkfarm attr set.${attr};
      }) (builtins.attrNames set));
in linkfarm
