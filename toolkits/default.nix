{ callPackage }:
rec {
  deps = {
    libffi_3_2_1 = callPackage ./deps/libffi_3_2_1.nix { };
    opencl-clang_14 = callPackage ./deps/opencl-clang_14.nix { };
    gdbm_1_13 = callPackage ./deps/gdbm_1_13.nix { };
  };

  base = callPackage ./base.nix { inherit deps; };

  # The base dependency is only due to how it's packaged for nixpkgs
  # it does not actually depend on base, that's just how
  # installer.nix is de-duplicated
  hpc = callPackage ./hpc.nix { inherit base; };
}
