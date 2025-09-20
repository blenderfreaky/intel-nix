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
  version = "unstable-2025-09-16";

  src = fetchFromGitHub {
    owner = "ggml-org";
    repo = "ggml";
    # tag = "heads/sync-llama.cpp-25-06-01";
    rev = "978f6e1993f2eeb4e99b63d4e70b4401c0a2dae2";
    hash = "sha256-y+5oyzn4XENMqWWuDVEN8TELYBcJJbA545gwi+82fb4=";
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
