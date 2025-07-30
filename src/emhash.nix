{
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
}:
stdenv.mkDerivation {
  pname = "emhash";
  version = "todo";

  src = fetchFromGitHub {
    owner = "ktprime";
    repo = "emhash";
    rev = "3ba9abdfdc2e0430fcc2fd8993cad31945b6a02b";
    sha256 = "sha256-w/iW5n9BzdiieZfxnVBF5MJTpHtZoWCUomjZ0h4OGH8=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  cmakeFlags = ["-DCMAKE_CXX_FLAGS='-msse4.1'"];
}
