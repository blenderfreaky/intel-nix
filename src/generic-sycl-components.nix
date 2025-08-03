{
  fetchFromGitHub,
  llvm,
  cmake,
  ninja,
}:
llvm.stdenv.mkDerivation {
  pname = "generic-sycl-components";
  version = "todo";

  src = fetchFromGitHub {
    owner = "uxlfoundation";
    repo = "generic-sycl-components";
    rev = "aa3d4c6791639df9c3112db143ab1caa7fa4f605";
    hash = "sha256-ezw0UBcrHEgzBO6VF9kCJHyw3qyltspi80RucNpexLM=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

}
