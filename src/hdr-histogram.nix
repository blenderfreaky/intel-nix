{
  fetchFromGitHub,
  stdenv,
  cmake,
  ninja,
  zlib,
}: let
  version = "0.11.8";
in
  stdenv.mkDerivation {
    pname = "HdrHistogram_c";
    inherit version;

    src = fetchFromGitHub {
      owner = "HdrHistogram";
      repo = "HdrHistogram_c";
      tag = version;
      hash = "sha256-TFlrC4bgK8o5KRZcLMlYU5EO9Oqaqe08PjJgmsUl51M=";
    };

    nativeBuildInputs = [
      cmake
      ninja
    ];

    buildInputs = [
      zlib
    ];
  }
