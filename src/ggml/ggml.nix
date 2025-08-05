{
  fetchFromGitHub,
  llvm,
  cmake,
  ninja,
  oneDNN,
  oneMath,
  oneTBB,
  mkl,
  git,
  opencl-headers,
  ocl-icd,
}:
llvm.stdenv.mkDerivation {
  pname = "ggml";
  version = "todo";

  src = fetchFromGitHub {
    owner = "ggml-org";
    repo = "ggml";
    # tag = "heads/sync-llama.cpp-25-06-01";
    rev = "d0f7473c";
    hash = "sha256-IJaT+2MhBUo7TjzNJaUZyeL1aQ/p1lwTZpiiH14s+qA=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    git
  ];

  buildInputs = [
    oneDNN
    oneMath
    oneTBB
    mkl
    opencl-headers
    ocl-icd
  ];

  hardeningDisable = [
    "zerocallusedregs"
    "pacret"
    # "shadowstack"
  ];

  cmakeFlags = [
    "-DGGML_SYCL=ON"
  ];
}
