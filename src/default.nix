{ callPackage }:
rec {
  llvm = callPackage ./llvm { inherit unified-runtime; };
  unified-runtime = callPackage ./unified-runtime.nix { inherit unified-memory-framework; };
  unified-memory-framework = callPackage ./unified-memory-framework.nix { };

  ur-test = callPackage ./unified-runtime.nix {
    inherit unified-memory-framework;
    buildTests = true;
  };
}
