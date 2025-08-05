{
  llvm,
  cmake,
  ninja,
  fetchFromGitHub,
  oneTBB,
  ocl-icd,
  gcc,
  lib,
}:
let
  version = "3.8.1";
in
llvm.stdenv.mkDerivation {
  pname = "onednn";
  inherit version;

  src = fetchFromGitHub {
    owner = "uxlfoundation";
    repo = "oneDNN";
    tag = "v${version}";
    hash = "sha256-x4leRd0xPFUygjAv/D125CIXn7lYSyzUKsd9IDh/vCc=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  buildInputs = [
    oneTBB
    ocl-icd
    llvm.baseLlvm.openmp
    gcc
  ];

  hardeningDisable = [
    "zerocallusedregs"
    "pacret"
    # "shadowstack"
  ];

  cmakeFlags = [
    (lib.cmakeFeature "ONEDNN_CPU_RUNTIME" "SYCL")
    (lib.cmakeFeature "ONEDNN_GPU_RUNTIME" "SYCL")
  ];
}
