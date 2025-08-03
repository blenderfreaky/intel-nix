{
  fetchFromGitHub,
  lib,
  llvm,
  cmake,
  ninja,
  mkl,
  tbb_2022,
}:
let
  version = "0.8";
in
llvm.stdenv.mkDerivation {
  pname = "oneMath";
  version = version;
  src = fetchFromGitHub {
    owner = "uxlfoundation";
    repo = "oneMath";
    rev = "v${version}";
    sha256 = "sha256-xK8lKI3oqKlx3xtvdScpMq+HXAuoYCP0BZdkEqnJP5o=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  buildInputs = [
    mkl
    tbb_2022
  ];

  cmakeFlags = [
    # (lib.cmakeFeature "CMAKE_C_COMPILER" "${llvm}/bin/clang")
    # (lib.cmakeFeature "CMAKE_CXX_COMPILER" "${llvm}/bin/clang++")

    # Requires closed source icpx
    (lib.cmakeBool "ENABLE_MKLCPU_BACKEND" false)
    (lib.cmakeBool "ENABLE_MKLGPU_BACKEND" false)

    (lib.cmakeBool "ENABLE_GENERIC_BLAS_BACKEND" true)

    (lib.cmakeBool "BUILD_FUNCTIONAL_TESTS" false)
    (lib.cmakeBool "BUILD_EXAMPLES" false)
  ];
}
