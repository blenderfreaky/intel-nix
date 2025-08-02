{
  callPackage,
  wrapCC,
  llvmPackages_21,
  overrideCC,
  unified-runtime,
}: rec {
  llvm-unwrapped = callPackage ./unwrapped.nix {inherit unified-runtime;};

  llvm = wrapCC llvm-unwrapped;

  stdenv = overrideCC llvmPackages_21.stdenv llvm;
}
