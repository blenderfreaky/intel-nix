{ callPackage }:
rec {
  llvm = callPackage ./llvm { inherit unified-runtime; };

  unified-runtime = callPackage ./unified-runtime.nix { inherit unified-memory-framework; };
  unified-memory-framework = callPackage ./unified-memory-framework.nix { };

  emhash = callPackage ./emhash.nix { };
  vc-intrinsics = callPackage ./vc-intrinsics.nix { };

  oneMath = callPackage ./onemath.nix { inherit llvm; };
  oneDNN = callPackage ./onednn.nix { inherit llvm; };
  generic-sycl-components = callPackage ./generic-sycl-components.nix { inherit llvm; };

  khronos-sycl-cts = callPackage ./khronos-sycl-cts.nix { mkDerivation = llvm.stdenv.mkDerivation; };
}
