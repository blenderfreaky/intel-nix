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
  vc-intrinsics,
  sphinx,
  doxygen,
  level-zero,
  libcxx,
  libxml2,
  libedit,
  llvmPackages_21,
  callPackage,
  spirv-tools,
  intel-compute-runtime,
  # opencl-headers,
  # emhash,
  zlib,
  wrapCC,
  ctestCheckHook,
  rocmPackages ? {},
  levelZeroSupport ? true,
  openclSupport ? true,
  # Broken
  cudaSupport ? false,
  rocmSupport ? true,
  rocmGpuTargets ? builtins.concatStringsSep ";" rocmPackages.clr.gpuTargets,
  nativeCpuSupport ? false,
  vulkanSupport ? true,
  useLibcxx ? false,
  useLdd ? false,
  buildTests ? false,
  buildDocs ? false,
  buildMan ? false,
}: let
  version = "unstable-2025-08-12";
  date = "20250812";
  deps = callPackage ./deps.nix {};
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
  # See the postPatch phase for details on why this is used
  ccWrapperStub = wrapCC (
    stdenv.mkDerivation {
      name = "ccWrapperStub";
      dontUnpack = true;
      installPhase = let
        root = "/build/source/build";
      in ''
        mkdir -p $out/bin
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
  stdenv.mkDerivation {
    pname = "intel-llvm";
    inherit version;

    src = fetchFromGitHub {
      owner = "intel";
      repo = "llvm";
      # tag = "sycl-web/sycl-latest-good";
      rev = "0e0984eec8008f4f6cb8b3bf6c2811f0dd8faa94";
      hash = "sha256-AkAwc7JjvDcuXq5lGavnUsE8GKfiPV5CCR18InPl8ws=";
    };

    # I'd like to split outputs, but currently this fails
    # outputs = [
    #   "out"
    #   "lib"
    #   "dev"
    #   "rsrc"
    # ];

    nativeBuildInputs =
      [
        cmake
        ninja
        python3
        pkg-config
      ]
      ++ lib.optionals useLdd [
        llvmPackages_21.bintools
      ];

    buildInputs =
      [
        zstd
        sphinx
        doxygen
        spirv-tools
        libxml2
        valgrind.dev
        zlib
        libedit
        hwloc
        vc-intrinsics
        intel-compute-runtime
        # TODO: Package separately
        # emhash
      ]
      ++ lib.optionals useLibcxx [
        libcxx
        libcxx.dev
      ]
      ++ unified-runtime'.buildInputs;

    # TODO: Is this needed?
    nativeCheckInputs = lib.optionals buildTests [
      ctestCheckHook
    ];

    postPatch = ''
      # The latter is used everywhere except this one file. For some reason,
      # the former is not set, at least when building with Nix, so we replace it.
      # See also: github.com/intel/llvm/pull/19637
      substituteInPlace unified-runtime/cmake/helpers.cmake \
        --replace-fail "PYTHON_EXECUTABLE" "Python3_EXECUTABLE"

      # When running without this, their CMake code copies files from the Nix store.
      # As the Nix store is read-only and COPY copies permissions by default,
      # this will lead to the copied files also being read-only.
      # As CMake at a later point wants to write into copied folders, this causes
      # the build to fail with a (rather cryptic) permission error.
      # By setting NO_SOURCE_PERMISSIONS we side-step this issue.
      # Note in case of future build failures: if there are executables in any of the copied folders,
      # we may need to add special handling to set the executable permissions.
      # See also: https://github.com/intel/llvm/issues/19635#issuecomment-3134830708
      sed -i '/file(COPY / { /NO_SOURCE_PERMISSIONS/! s/)\s*$/ NO_SOURCE_PERMISSIONS)/ }' \
        unified-runtime/cmake/FetchLevelZero.cmake \
        sycl/CMakeLists.txt \
        sycl/cmake/modules/FetchEmhash.cmake

      # Parts of libdevice are built using the freshly-built compiler.
      # As it tries to link to system libraries, we need to wrap it with the
      # usual nix cc-wrapper.
      # Since the compiler to be wrapped is not available at this point,
      # we use a stub that points to where it will be later on
      # in `/build/source/build/bin/clang-21`
      # Note: both nix and bash try to expand clang_exe here, so double-escape it
      substituteInPlace libdevice/cmake/modules/SYCLLibdevice.cmake \
        --replace-fail "\''${clang_exe}" "${ccWrapperStub}/bin/clang++"

      # Some libraries check for the version of the compiler.
      # For some reason, this version is determined by the
      # date of compilation. As the nix sandbox tells CMake
      # it's running at Unix epoch, this will always result in
      # a waaaay too old version.
      # To avoid this, we set the version to a fixed value.
      # See also: https://github.com/intel/llvm/issues/19692
      substituteInPlace sycl/CMakeLists.txt \
        --replace-fail 'string(TIMESTAMP __SYCL_COMPILER_VERSION "%Y%m%d")' 'set(__SYCL_COMPILER_VERSION "${date}")'
    '';

    preConfigure = ''
      flags=$(python buildbot/configure.py \
          --print-cmake-flags \
          -t Release \
          --docs \
          --cmake-gen Ninja \
          ${lib.optionalString cudaSupport "--cuda"} \
          ${lib.optionalString rocmSupport "--hip"} \
          ${lib.optionalString nativeCpuSupport "--native_cpu"} \
          ${lib.optionalString useLibcxx "--use-libcxx"} \
          ${lib.optionalString useLibcxx "--libcxx-include ${lib.getInclude libcxx}/include"} \
          ${lib.optionalString useLibcxx "--libcxx-library ${lib.getLib libcxx}/lib"} \
          ${lib.optionalString useLdd "--use-lld"} \
          ${lib.optionalString levelZeroSupport "--level_zero_adapter_version V1"} \
          ${lib.optionalString levelZeroSupport "--l0-headers ${lib.getInclude level-zero}/include/level_zero"} \
          ${lib.optionalString levelZeroSupport "--l0-loader ${lib.getLib level-zero}/lib/libze_loader.so"} \
          # --enable-all-llvm-targets
          # --shared-libs # Bad and should not be used
      )


      # We eval because flags is separated as shell-escaped strings.
      # We can't just split by space because it may contain escaped spaces,
      # so we just let bash handle it.
      # TODO: This may not be necessary
      # NOTE: We prepend, so that flags we set manually override what the build script does.
      eval "prependToVar cmakeFlags $flags"

      # Remove the install prefix flag
      cmakeFlags=(''${cmakeFlags[@]/-DCMAKE_INSTALL_PREFIX=\/build\/source\/build\/install})
    '';

    cmakeDir = "/build/source/llvm";

    cmakeFlags =
      [
        # (lib.cmakeFeature "LLVM_TARGETS_TO_BUILD" (lib.concatStringsSep ";" llvmTargetsToBuild'))
        # (lib.cmakeFeature "LLVM_ENABLE_PROJECTS" (lib.concatStringsSep ";" llvmProjectsToBuild))
        (lib.cmakeFeature "LLVM_HOST_TRIPLE" stdenv.hostPlatform.config)
        (lib.cmakeFeature "LLVM_DEFAULT_TARGET_TRIPLE" stdenv.hostPlatform.config)
        (lib.cmakeBool "LLVM_INSTALL_UTILS" true)
        (lib.cmakeBool "LLVM_INCLUDE_DOCS" (buildDocs || buildMan))
        (lib.cmakeBool "MLIR_INCLUDE_DOCS" (buildDocs || buildMan))
        (lib.cmakeBool "LLVM_BUILD_DOCS" (buildDocs || buildMan))
        # # Way too slow, only uses one core
        # # (lib.cmakeBool "LLVM_ENABLE_DOXYGEN" (buildDocs || buildMan))
        (lib.cmakeBool "LLVM_ENABLE_SPHINX" (buildDocs || buildMan))
        (lib.cmakeBool "SPHINX_OUTPUT_HTML" buildDocs)
        (lib.cmakeBool "SPHINX_OUTPUT_MAN" buildMan)
        # (lib.cmakeBool "SPHINX_WARNINGS_AS_ERRORS" false)
        (lib.cmakeBool "LLVM_BUILD_TESTS" buildTests)
        (lib.cmakeBool "LLVM_INCLUDE_TESTS" buildTests)
        (lib.cmakeBool "MLIR_INCLUDE_TESTS" buildTests)
        (lib.cmakeBool "SYCL_INCLUDE_TESTS" buildTests)

        (lib.cmakeBool "LLVM_BUILD_LLVM_DYLIB" true)

        (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
        (lib.cmakeBool "FETCHCONTENT_QUIET" false)

        #(lib.cmakeFeature "LLVMGenXIntrinsics_SOURCE_DIR" "${deps.vc-intrinsics}")
        # This can be changed to (pkgs.) spirv-headers.src once they release a new version and nix updates to that
        (lib.cmakeFeature "LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR" "${deps.spirv-headers}")

        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_EMHASH" "${deps.emhash}")
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_PARALLEL-HASHMAP" "${deps.parallel-hashmap}")

        # These can be switched over to nixpkgs versions once they're updated
        # See: https://github.com/NixOS/nixpkgs/pull/428558
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-HEADERS" "${deps.opencl-headers}")
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-ICD" "${deps.opencl-icd-loader}")

        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ONEAPI-CK" "${deps.oneapi-ck}")
      ]
      ++ unified-runtime'.cmakeFlags;

    # This hardening option causes compilation errors when compiling for amdgcn, spirv and others
    # TODO: Can the cc wrapper be made aware of this somehow?
    hardeningDisable = ["zerocallusedregs"];

    # TODO: Investigate why this is needed
    NIX_LDFLAGS = "-lhwloc";

    requiredSystemFeatures = ["big-parallel"];
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
      maintainers = with maintainers; [blenderfreaky];
      platforms = platforms.linux;
    };

    passthru = {
      isClang = true;
      # The llvm package set of the same version as
      # Intels compiler is based on
      baseLlvm = llvmPackages_21;
    };
  }
