{
  stdenv,
  lib,
  fetchFromGitHub,
  cmake,
  ninja,
  python3,
  llvmPackages_21,
}: let
  version = "60cea7590bd022d95f5cf336ee765033bd114d69";
in
  stdenv.mkDerivation {
    pname = "vc-intrinsics";
    inherit version;
    #https://github.com/intel/vc-intrinsics
    src = fetchFromGitHub {
      owner = "intel";
      repo = "vc-intrinsics";
      rev = version;
      hash = "sha256-1K16UEa6DHoP2ukSx58OXJdtDWyUyHkq5Gd2DUj1644=";
    };

    nativeBuildInputs = [
      cmake
      ninja
      python3
    ];
    # buildInputs = [ llvmPackages_21.libllvm.dev ];

    cmakeFlags = [
      (lib.cmakeFeature "LLVM_DIR" "${lib.getDev llvmPackages_21.llvm}/lib/cmake/llvm")
      # (lib.cmakeBool "BUILD_EXTERNAL" true)
      # (lib.cmakeBool "LLVM_LINK_LLVM_DYLIB" false)
    ];
  }
