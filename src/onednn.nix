{
  llvm,
  cmake,
  ninja,
  fetchFromGitHub,
  tbb,
  ocl-icd,
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
    tbb
    ocl-icd
    llvm.baseLlvm.openmp
  ];

}
