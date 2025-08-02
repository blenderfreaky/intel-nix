{callPackage}: rec {
  llvm = callPackage ./llvm {inherit unified-runtime;};

  unified-runtime = callPackage ./unified-runtime.nix {inherit unified-memory-framework;};
  unified-memory-framework = callPackage ./unified-memory-framework.nix {};

  emhash = callPackage ./emhash.nix {};
  vc-intrinsics = callPackage ./vc-intrinsics.nix {};

  oneMath = callPackage ./onemath.nix {inherit llvm;};
}
