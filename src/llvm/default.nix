{
  callPackage,
  wrapCC,
  symlinkJoin,
  overrideCC,
  unified-runtime,
  vc-intrinsics,
}: let
  llvm-unwrapped = callPackage ./unwrapped.nix {inherit unified-runtime vc-intrinsics;};
  llvm-wrapper = wrapCC llvm-unwrapped;
  llvm = symlinkJoin {
    inherit (llvm-unwrapped) pname version meta;

    # Order is important, we want files from the wrapper to take precedence
    paths = [
      llvm-wrapper
      llvm-unwrapped
    ];

    passthru =
      llvm-unwrapped.passthru
      // {
        inherit stdenv;
        unwrapped = llvm-unwrapped;
      };
  };
  stdenv = overrideCC llvm-unwrapped.baseLlvm.stdenv llvm;
in
  llvm
