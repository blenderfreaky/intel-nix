{
  fetchFromGitHub,
  llvm,
  cmake,
  ninja,
  lib,
}:
llvm.stdenv.mkDerivation (finalAttrs: {
  # TODO: Figure out how to name this for nix
  pname = "onemath-sycl-blas";
  # TODO: Open issue for tagged releases; oneMath currently uses FetchContent to pull `main` which is irreproducible
  version = "todo";

  src = fetchFromGitHub {
    owner = "uxlfoundation";
    repo = "generic-sycl-components";
    rev = "aa3d4c6791639df9c3112db143ab1caa7fa4f605";
    hash = "sha256-ezw0UBcrHEgzBO6VF9kCJHyw3qyltspi80RucNpexLM=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  # cmakeDir = "onemath/sycl/blas";
  sourceRoot = "${finalAttrs.src.name}/onemath/sycl/blas";

  cmakeFlags = [
    # TODO: INTEL_GPU, NVIDIA_GPU, AMD_GPU
    (lib.cmakeFeature "TUNING_TARGET" "DEFAULT")
  ];
})
