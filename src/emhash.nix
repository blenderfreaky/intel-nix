{
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
}:
stdenv.mkDerivation {
  pname = "emhash";
  version = "unstable-2025-08-10";

  src = fetchFromGitHub {
    owner = "ktprime";
    repo = "emhash";
    rev = "4867731d6f631e63deb99278f1dccfc7b01783b6";
    hash = "sha256-TUQGxN86nf88eU2AtRVMycTLhGavxTP7el+icDe2iaY=";
  };

  nativeBuildInputs = [
    cmake
    # ninja
  ];

  cmakeFlags = [
    "-DCMAKE_CXX_FLAGS='-msse4.1'"
    "-DWITH_BENCHMARKS=Off"
  ];
  #
  # dontBuild = true;

  # installPhase = ''
  #   mkdir -p $out
  #   cp emhash $out/bin/
  # '';
}
