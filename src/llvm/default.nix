{
  callPackage,
  wrapCC,
  unified-runtime,
}: rec {
  llvm-unwrapped = callPackage ./unwrapped.nix {inherit unified-runtime;};

  llvm = wrapCC llvm-unwrapped;
}
