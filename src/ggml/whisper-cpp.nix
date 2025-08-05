{
  fetchFromGitHub,
  llvm,
  cmake,
  ninja,
  oneDNN,
  oneMath,
  oneTBB,
  # mkl,
  git,
  opencl-headers,
  ocl-icd,
}: let
  version = "1.7.6";
in
  llvm.stdenv.mkDerivation {
    pname = "whisper-cpp";
    inherit version;

    src = fetchFromGitHub {
      owner = "ggml-org";
      repo = "whisper.cpp";
      tag = "v${version}";
      hash = "sha256-dppBhiCS4C3ELw/Ckx5W0KOMUvOHUiisdZvkS7gkxj4=";
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
      # mkl
      opencl-headers
      ocl-icd
    ];

    hardeningDisable = [
      "zerocallusedregs"
      "pacret"
      # "shadowstack"
    ];

    cmakeFlags = [
      "-DWHISPER_SYCL=ON"
    ];
  }
