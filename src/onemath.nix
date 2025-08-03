{
  fetchFromGitHub,
  lib,
  llvm,
  cmake,
  ninja,
  mkl,
  tbb_2022,
  oneMath-sycl-blas,
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
    # mkl
    tbb_2022
    oneMath-sycl-blas
  ];

  cmakeFlags = [
    # (lib.cmakeFeature "CMAKE_C_COMPILER" "${llvm}/bin/clang")
    # (lib.cmakeFeature "CMAKE_CXX_COMPILER" "${llvm}/bin/clang++")

    # Requires closed source icpx + mkl
    (lib.cmakeBool "ENABLE_MKLCPU_BACKEND" false)
    (lib.cmakeBool "ENABLE_MKLGPU_BACKEND" false)
    (lib.cmakeBool "ENABLE_CUBLAS_BACKEND" false)
    (lib.cmakeBool "ENABLE_CUSOLVER_BACKEND" false)
    (lib.cmakeBool "ENABLE_CUFFT_BACKEND" false)
    (lib.cmakeBool "ENABLE_CURAND_BACKEND" false)
    (lib.cmakeBool "ENABLE_CUSPARSE_BACKEND" false)
    (lib.cmakeBool "ENABLE_NETLIB_BACKEND" false)
    (lib.cmakeBool "ENABLE_ARMPL_BACKEND" false)
    (lib.cmakeBool "ENABLE_ARMPL_OMP" true)
    (lib.cmakeBool "ENABLE_ARMPL_OPENRNG" false)
    (lib.cmakeBool "ENABLE_ROCBLAS_BACKEND" false)
    (lib.cmakeBool "ENABLE_ROCFFT_BACKEND" false)
    (lib.cmakeBool "ENABLE_ROCSOLVER_BACKEND" false)
    (lib.cmakeBool "ENABLE_ROCRAND_BACKEND" false)
    (lib.cmakeBool "ENABLE_ROCSPARSE_BACKEND" false)
    (lib.cmakeBool "ENABLE_MKLCPU_THREAD_TBB" true)
    # Required onemath-sycl-blas
    (lib.cmakeBool "ENABLE_GENERIC_BLAS_BACKEND" true)
    (lib.cmakeBool "ENABLE_PORTFFT_BACKEND" false)
    (lib.cmakeBool "BUILD_FUNCTIONAL_TESTS" true)
    (lib.cmakeBool "BUILD_EXAMPLES" true)

    (lib.cmakeBool "BUILD_FUNCTIONAL_TESTS" false)
    (lib.cmakeBool "BUILD_EXAMPLES" false)
  ];
}
