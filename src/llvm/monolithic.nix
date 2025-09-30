{
  callPackage,
  wrapCC,
  symlinkJoin,
  overrideCC,
  unified-runtime,
  emhash,
  vc-intrinsics,
  ccacheStdenv,
}: let
  llvm-unwrapped = callPackage ./monolithic-unwrapped.nix {inherit unified-runtime emhash vc-intrinsics;};
  llvm-wrapper = wrapCC llvm-unwrapped;
  llvm = symlinkJoin {
    inherit (llvm-unwrapped) pname version meta;

    # Order is important, we want files from the wrapper to take precedence
    paths = [
      llvm-wrapper
      llvm-unwrapped
      llvm-unwrapped.dev
      llvm-unwrapped.lib
    ];

    passthru =
      llvm-unwrapped.passthru
      // {
        inherit stdenv;
        unwrapped = llvm-unwrapped;
        openmp = llvm-unwrapped.baseLlvm.openmp;
      };
  };
  stdenv = overrideCC llvm-unwrapped.baseLlvm.stdenv llvm;
  #stdenv' = overrideCC llvm-unwrapped.baseLlvm.stdenv llvm;
  #stdenv = ccacheStdenv.override {stdenv = stdenv';};
in
  llvm
