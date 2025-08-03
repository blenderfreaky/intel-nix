{
  fetchFromGitHub,
  mkDerivation,
  python3,
  cmake,
  ninja,
}:
mkDerivation {
  pname = "khronos-sycl-cts";
  version = "todo";

  src = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SYCL-CTS";
    rev = "ea1d62ba042079bca045b47ec30c06863f899a1a";
    hash = "sha256-KrRpkqfoF2CvIneE0l4Km9RHdqMU3Zf47W2QI72UwRQ=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    python3
    cmake
    ninja
  ];

  hardeningDisable = [
    "zerocallusedregs"
    "pacret"
    # "shadowstack"
  ];

  cmakeFlags = [
    # TODO: Make parameter
    "-DSYCL_IMPLEMENTATION=DPCPP"
  ];
}
