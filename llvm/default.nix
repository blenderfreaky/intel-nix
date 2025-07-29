{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  python3,
  pkg-config,
  zstd,
  hwloc,
  valgrind,
  # We use the in-tree unified-runtime, but we need all the same flags as the out-of-tree version.
  # Rather than duplicating the flags, we can simply use the existing flags.
  # We can also use this to debug unified-runtime without building the entire LLVM project.
  unified-runtime,
  sphinx,
  level-zero,
  libcxx,
  libxml2,
  libedit,
  lld,
  callPackage,
  spirv-tools,
  zlib,
  #clang-tools,
  wrapCC,
  rocmPackages ? { },
  levelZeroSupport ? true,
  openclSupport ? true,
  # Broken
  cudaSupport ? false,
  rocmSupport ? true,
  rocmGpuTargets ? builtins.concatStringsSep ";" rocmPackages.clr.gpuTargets,
  nativeCpuSupport ? true,
  vulkanSupport ? true,
  useLibcxx ? false,
  useLdd ? true,
  buildTests ? false,
}:
let
  version = "nightly-2025-07-18";
  deps = callPackage ./deps.nix { };
  unified-runtime' = unified-runtime.override {
    inherit
      levelZeroSupport
      openclSupport
      cudaSupport
      rocmSupport
      rocmGpuTargets
      nativeCpuSupport
      vulkanSupport
      buildTests
      ;
  };
  ccWrapperStub = wrapCC (
    stdenv.mkDerivation {
      name = "ccWrapperStub";
      dontUnpack = true;
      installPhase =
        let
          #root = ".";
          #root = "/home/blenderfreaky/src/stuff/intel/intel-llvm/build";
          root = "/build/source/build";
        in
        ''
          mkdir -p $out/bin
          #for bin in clang
          #do
          #  cat > $out/bin/$bin <<EOF
          ##!/bin/sh
          #exec "${root}/bin/$bin" "\$@"
          #EOF
          #  chmod +x $out/bin/$bin
          #done
          cat > $out/bin/clang++ <<EOF
          #!/bin/sh
          exec "${root}/bin/clang-21" "\$@"
          EOF
          chmod +x $out/bin/clang++
        '';
      passthru.isClang = true;
    }
  );
in
stdenv.mkDerivation rec {
  pname = "intel-llvm";
  inherit version;

  src = fetchFromGitHub {
    owner = "intel";
    repo = "llvm";
    tag = "sycl-web/sycl-latest-good";
    sha256 = "sha256-xbmZOHTi4DMu53GEoqH2JKuGQh8Kd/srqS3+YR0Jvqg=";
  };

  # # Otherwise llvm-min-tblgen fails for some reason
  # NIX_CFLAGS_COMPILE = "-static-libstdc++";

  nativeBuildInputs = [
    cmake
    ninja
    python3
    pkg-config
  ]
  ++ lib.optionals useLdd [
    lld
  ];

  buildInputs = [
    zstd
    sphinx
    spirv-tools
    libxml2
    valgrind.dev
    zlib
    libedit
    # stdenv.cc.libc
    # stdenv.cc.cc.lib
    # libgcc.lib
    zlib
    #clang-tools
    hwloc
  ]
  ++ lib.optionals useLibcxx [
    libcxx
    libcxx.dev
  ]
  ++ unified-runtime'.buildInputs;

  postPatch = ''
    # The latter is used everywhere except this one file. For some reason,
    # the former is not set, at least when building with Nix, so we replace it.
    substituteInPlace unified-runtime/cmake/helpers.cmake \
      --replace-fail "PYTHON_EXECUTABLE" "Python3_EXECUTABLE"

    sed -i '/file(COPY / { /NO_SOURCE_PERMISSIONS/! s/)\s*$/ NO_SOURCE_PERMISSIONS)/ }' \
        unified-runtime/cmake/FetchLevelZero.cmake \
        sycl/CMakeLists.txt \
        sycl/cmake/modules/FetchEmhash.cmake

    # Note: both nix and bash try to expand clang_exe here, so double-escape it
    substituteInPlace libdevice/cmake/modules/SYCLLibdevice.cmake \
      --replace-fail "\''${clang_exe}" "${ccWrapperStub}/bin/clang++"

    # cat libdevice/cmake/modules/SYCLLibdevice.cmake
    # NIX_DEBUG=1 gcc fake.cpp || true
    echo $ninjaInstallPhase
    echo $installPhase
  '';

  # preConfigure = ''
  #   # For some reason, it doesn't create this on its own,
  #   # causing a cryptic Permission denied error.
  #   mkdir -p /build/source/build/unified-runtime/source/common/level_zero_loader/level_zero/

  #   mkdir -p /build/source/build/include/{sycl,CL,std,syclcompat}
  # '';

  cmakeFlags = [
    (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
    (lib.cmakeBool "FETCHCONTENT_QUIET" false)

    (lib.cmakeFeature "LLVMGenXIntrinsics_SOURCE_DIR" "${deps.vc-intrinsics}")
    (lib.cmakeFeature "LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR" "${deps.spirv-headers}")

    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_EMHASH" "${deps.emhash}")
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_PARALLEL-HASHMAP" "${deps.parallel-hashmap}")
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-HEADERS" "${deps.opencl-headers}")
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-ICD" "${deps.opencl-icd-loader}")
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ONEAPI-CK" "${deps.oneapi-ck}")

    # This is for llvm-min-tblgen, which is built and then immediately ran by CMake.
    # (lib.cmakeBool "CMAKE_BUILD_WITH_INSTALL_RPATH" true)
    # (lib.cmakeFeature "CMAKE_INSTALL_RPATH" "${
    #   lib.makeLibraryPath [
    #     stdenv.cc.cc.lib
    #     zlib
    #   ]
    # }:/build/source/build/lib")
    # (lib.cmakeFeature "CMAKE_EXE_LINKER_FLAGS" "-Wl,-rpath,${
    #   lib.makeLibraryPath [
    #     stdenv.cc.cc.lib
    #     zlib
    #   ]
    # }:/build/source/build/lib")
  ]
  ++ unified-runtime'.cmakeFlags;

  hardeningDisable = lib.optionals rocmSupport [ "zerocallusedregs" ];

  configurePhase = ''
    runHook preConfigure

    python buildbot/configure.py \
    -t Release \
    --docs \
    --shared-libs \
    --cmake-gen Ninja \
    --l0-headers ${lib.getInclude level-zero}/include/level_zero \
    --l0-loader ${lib.getLib level-zero}/lib/libze_loader.so \
    ${lib.optionalString cudaSupport "--cuda"} \
    ${lib.optionalString rocmSupport "--hip"} \
    ${lib.optionalString nativeCpuSupport "--native_cpu"} \
    ${lib.optionalString useLibcxx "--use-libcxx"} \
    ${lib.optionalString useLibcxx "--libcxx-include ${lib.getInclude libcxx}/include"} \
    ${lib.optionalString useLibcxx "--libcxx-library ${lib.getLib libcxx}/lib"} \
    ${lib.optionalString useLdd "--use-lld"} \
    ${lib.optionalString levelZeroSupport "--level_zero_adapter_version V1"} \
    $cmakeFlags
    #--cmake-opt '${lib.strings.concatStringsSep " " cmakeFlags}'

    # --enable-all-llvm-targets \
    #


    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    export LD_LIBRARY_PATH="${
      lib.makeLibraryPath [
        stdenv.cc.cc.lib
        zlib
        hwloc
      ]
    }:/build/source/build/lib"

    python buildbot/compile.py --verbose

    runHook postBuild
  '';

  # TODO: This may actually be obsolete with the wrapping in-place now
  NIX_LDFLAGS = "-lhwloc";

  requiredSystemFeatures = [ "big-parallel" ];
  enableParallelBuilding = true;

  doCheck = true;

  meta = with lib; {
    description = "Intel LLVM-based compiler with SYCL support";
    longDescription = ''
      Intel's LLVM-based compiler toolchain with Data Parallel C++ (DPC++)
      and SYCL support for heterogeneous computing across CPUs, GPUs, and FPGAs.
    '';
    homepage = "https://github.com/intel/llvm";
    # TODO: Apache with LLVM exceptions
    # license = with licenses; [ ncsa ];
    maintainers = with maintainers; [ blenderfreaky ];
    platforms = platforms.linux;
  };

  passthru = {
    isClang = true;
    inherit version;
  };
}
