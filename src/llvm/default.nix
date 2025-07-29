{
  callPackage,
  wrapCC,
}: rec {
  llvm-unwrapped = callPackage ./unwrapped.nix {};

  llvm = wrapCC llvm-unwrapped;
}
