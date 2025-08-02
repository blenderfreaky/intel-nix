{
  fetchFromGitHub,
  llvm,
  cmake,
  ninja,
}: let
  version = "0.8";
in
  llvm.stdenv.mkDerivation {
    pname = "oneMath";
    version = version;
    src = fetchFromGitHub {
      owner = "uxlfoundation";
      repo = "oneMath";
      rev = "v${version}";
      sha256 = "sha256-xK8lKI3oqKlx3xtvdScpMq+HXAuoYCP0BZdkEqnJP5o=";
    };

    nativeBuildInputs = [
      cmake
      ninja
    ];
  }
