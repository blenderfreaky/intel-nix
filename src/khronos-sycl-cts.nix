{
  lib,
  fetchFromGitHub,
  mkDerivation,
  python3,
  cmake,
  ninja,
  rocmPackages ? { },
  target ? "intel",
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

  # hardeningDisable = [
  #   "zerocallusedregs"
  #   "pacret"
  #   # "shadowstack"
  # ];

  hardeningDisable = [ "all" ];

  cmakeFlags = [
    # TODO: Make parameter
    (lib.cmakeFeature "SYCL_IMPLEMENTATION" "DPCPP")
  ]
  ++ lib.optional (target == "amd") (lib.cmakeFeature "DPCPP_TARGET_TRIPLES" "amdgcn-amd-amdhsa");

  # We need to set this via the shell because it contains spaces
  preConfigure = lib.optionalString (target == "amd") ''
    cmakeFlagsArray+=(
      "-DDPCPP_FLAGS=-Xsycl-target-backend;--offload-arch=gfx1030;--rocm-path=${rocmPackages.clr};--rocm-device-lib-path=${rocmPackages.rocm-device-libs}/amdgcn/bitcode"
    )
  '';
}
