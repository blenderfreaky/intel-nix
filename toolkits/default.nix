{callPackage}: rec {
  deps = {
    libffi_3_2_1 = callPackage ./deps/libffi_3_2_1.nix {};
    opencl-clang_14 = callPackage ./deps/opencl-clang_14.nix {};
    gdbm_1_13 = callPackage ./deps/gdbm_1_13.nix {};
  };

  installer = callPackage ./installer {inherit deps;};
}
