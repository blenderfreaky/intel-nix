{
  # llvm,
  stdenv,
  fetchFromGitHub,
  ctestCheckHook,
  lib,
  cmake,
  ninja,
  hwloc,
}: let
  version = "2022.2.0";
in
  stdenv.mkDerivation {
    pname = "oneTBB";
    inherit version;
    src = fetchFromGitHub {
      owner = "uxlfoundation";
      repo = "oneTBB";
      tag = "v${version}";
      hash = "sha256-ASQPAGm5e4q7imvTVWlmj5ON4fGEao1L5m2C5wF7EhI=";
    };

    nativeBuildInputs = [
      cmake
      ninja
      ctestCheckHook
    ];

    buildInputs = [
      hwloc
    ];

    cmakeFlags = [
      #   # I am *assuming* this may break things if it were on
      #   # TODO: Verify if it breaks things if on
      #   # NOTE: Seems like this only does things on Windows
      #   (lib.cmakeBool "TBB_VERIFY_DEPENDENCY_SIGNATURE" false)
      (lib.cmakeBool "TBB_TEST" false)
    ];
  }
