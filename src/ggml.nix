{
  fetchFromGitHub,
  llvm,
  cmake,
  ninja,
  oneDNN,
  oneMath,
  tbb_2022,
  mkl,
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
  ];

  buildInputs = [
    oneDNN
    oneMath
    tbb_2022
    mkl
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
