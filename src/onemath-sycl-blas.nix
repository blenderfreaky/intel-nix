{
  fetchFromGitHub,
  llvm,
  cmake,
  ninja,
  lib,
  # INTEL_GPU, NVIDIA_GPU, AMD_GPU
  gpuTarget ? "DEFAULT",
}:
llvm.stdenv.mkDerivation (finalAttrs: {
  # TODO: Figure out how to name this for nix
  pname = "oneMath-sycl-blas";
  version = "unstable-2025-08-04";

  src = fetchFromGitHub {
    owner = "uxlfoundation";
    repo = "generic-sycl-components";
    # There are currently no tagged releases, tracking issue:
    # https://github.com/uxlfoundation/generic-sycl-components/issues/16
    rev = "99241128f64b700392e4cfdd047caada024bf7dd";
    hash = "sha256-JIyWclCJVqrllP5zYFv8T9wurCLixAetLVzQYt27pGY=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  sourceRoot = "${finalAttrs.src.name}/onemath/sycl/blas";

  cmakeFlags = [
    (lib.cmakeFeature "TUNING_TARGET" gpuTarget)
  ];
})
