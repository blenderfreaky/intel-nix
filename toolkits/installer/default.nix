{
  callPackage,
  deps,
}: rec {
  base = callPackage ./base.nix {inherit deps;};

  # The base dependency is only due to how it's packaged for nixpkgs
  # it does not actually depend on base, that's just how
  # installer.nix is de-duplicated
  hpc = callPackage ./hpc.nix {inherit base;};
}
