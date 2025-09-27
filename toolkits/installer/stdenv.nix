{
  kit,
  stdenv,
  overrideCC,
  callPackage,
}: let
  # Get the wrapped Intel compiler from wrapper.nix
  wrappedKit = callPackage ./wrapper.nix {inherit kit;};
in
  # Create a stdenv that uses Intel compilers
  overrideCC stdenv wrappedKit.cc
