{
  callPackage,
  wrapCC,
  symlinkJoin,
  overrideCC,
  emhash,
  ccacheStdenv,
}: let
  llvm-unwrapped = callPackage ./monolithic-unwrapped.nix {inherit emhash;};
  # llvm-unwrapped = callPackage ./monolithic-unwrapped-fhs.nix {inherit unified-runtime emhash;};
  llvm-wrapper = (wrapCC llvm-unwrapped).overrideAttrs (old: {
    propagatedBuildInputs = (old.propagatedBuildInputs or []) ++ llvm-unwrapped.propagatedBuildInputs;
  });
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
        tests = callPackage ./tests.nix { inherit stdenv; };
      };
  };
  stdenv = overrideCC llvm-unwrapped.baseLlvm.stdenv llvm;
  #stdenv' = overrideCC llvm-unwrapped.baseLlvm.stdenv llvm;
  #stdenv = ccacheStdenv.override {stdenv = stdenv';};
in
  llvm
