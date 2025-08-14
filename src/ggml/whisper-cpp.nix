{ cmake
, fetchFromGitHub
, git
, lib
, llvm
, llvmPackages
, makeWrapper
, oneDNN
, oneMath
, oneTBB
, openvino
, SDL2
, opencl-headers
, ocl-icd
, openblas # NOTE: needed for now until whisper.cpp moves to OneMath
, runCommand
}:

let
  oneMathCmakeShim = runCommand "oneMathCmakeShim" {
    buildInputs = [
      oneMath
      opencl-headers
      ocl-icd
      llvm.baseLlvm.openmp
    ];
  } ''
    mkdir -p $out/lib/cmake/OpenCL
    mkdir -p $out/lib/cmake/MKL

    cat > $out/lib/cmake/MKL/MKLConfig.cmake <<EOF
add_library(MKL::MKL UNKNOWN IMPORTED GLOBAL)
set_target_properties(MKL::MKL PROPERTIES
  IMPORTED_LOCATION "${oneMath}/lib/libonemath.so"
  INTERFACE_INCLUDE_DIRECTORIES "${oneMath}/include"
)

add_library(MKL::MKL_SYCL::BLAS UNKNOWN IMPORTED GLOBAL)
set_target_properties(MKL::MKL_SYCL::BLAS PROPERTIES
  IMPORTED_LOCATION "${oneMath}/lib/libonemath_blas_generic.so"
  INTERFACE_LINK_LIBRARIES "${oneMath}/lib/libonemath.so;${llvm.baseLlvm.openmp}/lib/libiomp5.so"
  INTERFACE_INCLUDE_DIRECTORIES "${oneMath}/include"
)
EOF

    cat > $out/lib/cmake/OpenCL/OpenCLConfig.cmake <<EOF
if(NOT TARGET OpenCL::OpenCL)
  add_library(OpenCL::OpenCL UNKNOWN IMPORTED GLOBAL)
  set_target_properties(OpenCL::OpenCL PROPERTIES
    IMPORTED_LOCATION "${ocl-icd}/lib/libOpenCL.so"
    INTERFACE_INCLUDE_DIRECTORIES "${opencl-headers}/include"
    INTERFACE_LINK_LIBRARIES "${ocl-icd}/lib/libOpenCL.so"
  )
  set(OpenCL_FOUND TRUE PARENT_SCOPE)
  set(OpenCL_INCLUDE_DIRS "${opencl-headers}/include" PARENT_SCOPE)
  set(OpenCL_LIBRARIES "${ocl-icd}/lib/libOpenCL.so" PARENT_SCOPE)
  set(OpenCL_FOUND TRUE CACHE BOOL "OpenCL found")
  set(OpenCL_INCLUDE_DIRS "${opencl-headers}/include" CACHE PATH "OpenCL include dirs")
  set(OpenCL_LIBRARIES "${ocl-icd}/lib/libOpenCL.so" CACHE FILEPATH "OpenCL libraries")
endif()
EOF
    '';
in

llvm.stdenv.mkDerivation rec {
  name = "whisper-cpp";
  pname = "whisper-cpp";

  src = fetchFromGitHub {
    owner = "ggml-org";
    repo = "whisper.cpp";
    rev = "5527454cdb3e15d7e2b8a6e2afcb58cb61651fd2";
    hash = "sha256-dppBhiCS4C3ELw/Ckx5W0KOMUvOHUiisdZvkS7gkxj4=";
  };

  nativeBuildInputs = [
    cmake
    makeWrapper
    git
    oneMathCmakeShim
  ];

  buildInputs = [
    oneDNN
    oneTBB
    llvm.baseLlvm.openmp
    SDL2
    openvino
    oneMath
    opencl-headers
    ocl-icd
    openblas # NOTE: Needed currently for blas symbols
  ];

  postPatch = ''
    substituteInPlace ggml/src/ggml-sycl/dpct/helper.hpp \
      --replace 'namespace math = mkl;' '/* namespace math = mkl; */'
  '';

  preConfigure = ''
    if [ -f "ggml/src/ggml-sycl/CMakeLists.txt" ]; then
      echo "Modifying SYCL CMakeLists.txt to find OpenCL first"
      sed -i '/if (GGML_SYCL_TARGET STREQUAL "INTEL")/i\
  find_package(OpenCL REQUIRED)' ggml/src/ggml-sycl/CMakeLists.txt
    fi

    source ${openvino}/setupvars.sh || echo "OpenVINO setup completed with warnings!"
  '';

  hardeningDisable = [ "all" ]; # NOTE: Enable most hardenings eventually

  cmakeFlags = [
    "-DGGML_SYCL=ON"
    "-DWHISPER_OPENVINO=1"
    "-DWHISPER_SDL2=ON"

    "-DGGML_BLAS=ON"
    "-DGGML_BLAS_VENDOR=Generic"
    "-DBLAS_LIBRARIES=${oneMath}/lib/libonemath_blas_generic.so;${llvm.baseLlvm.openmp}/lib/libiomp5.so;${openblas}/lib/libopenblas.so"
    "-DBLAS_INCLUDE_DIRS=${openblas}/include"

    "-DCMAKE_PREFIX_PATH=${oneMathCmakeShim}/lib/cmake"
  ];

  postInstall = ''
    for binary in $out/bin/*; do
      if [[ -f "$binary" && -x "$binary" ]]; then
        wrapProgram "$binary" \
          --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib:/run/opengl-driver-32/lib:${openvino}/runtime/lib/intel64"
      fi
    done
  '';
}
