{
  lib,
  llvmPackages_21,
  callPackage,
  fetchFromGitHub,
  zlib,
  zstd,
  unified-runtime,
  hwloc,
  spirv-llvm-translator,
  spirv-tools,
  vc-intrinsics,
  intel-compute-runtime,
  # TODO: llvmPackages.libcxx? libcxxStdenv?
  libcxx,
  rocmPackages ? {},
  level-zero,
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
  version = "nightly-2025-08-05";
  date = "20250805";
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
  src = fetchFromGitHub {
    owner = "intel";
    repo = "llvm";
    # tag = "sycl-web/sycl-latest-good";
    rev = "542a00b45276bd9a24ba85c041b0d5535a896593";
    hash = "sha256-d6HdVeEZR0Ydl9JgdZTUtMwJ++SgzFjN39/c6Fi6ha0=";
  };
  stdenv =
    if useLibcxx
    then llvmPackages_21.libcxxStdenv
    else llvmPackages_21.stdenv;
  pkgs = llvmPackages_21.override (old: {
    # version = "todo";
    inherit stdenv src;

    version = "21.0.0-${src.rev}";

    officialRelease = {};

    monorepoSrc = src;

    doCheck = false;
  });
in {
  llvm = pkgs.llvm.overrideAttrs (old: {
    buildInputs =
      old.buildInputs
      ++ [
        zlib
        zstd

        hwloc
        spirv-llvm-translator
        spirv-tools

        vc-intrinsics

        # Not sure if this is needed
        intel-compute-runtime
        llvmPackages_21.bintools
      ]
      ++ unified-runtime'.buildInputs;

    cmakeFlags =
      old.cmakeFlags
      ++ [
        "-DCMAKE_BUILD_TYPE=Release"
        "-DLLVM_ENABLE_ZSTD=FORCE_ON"
        # This is broken. TODO: Fix
        # "-DLLVM_ENABLE_ZLIB=FORCE_ON"
        "-DLLVM_ENABLE_THREADS=ON"
        "-DLLVM_ENABLE_LTO=Thin"
        "-DLLVM_USE_LINKER=lld"

        (lib.cmakeBool "LLVM_ENABLE_LIBCXX" useLibcxx)
        (lib.cmakeFeature "CLANG_DEFAULT_CXX_STDLIB" (
          if useLibcxx
          then "libc++"
          else "libstdc++"
        ))

        (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
        (lib.cmakeBool "FETCHCONTENT_QUIET" false)

        (lib.cmakeFeature "LLVMGenXIntrinsics_SOURCE_DIR" "${deps.vc-intrinsics}")
        # We need the actual source code here, so we can't use the nix derivation
        (lib.cmakeFeature "LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR" "${deps.spirv-headers}")

        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_EMHASH" "${deps.emhash}")
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_PARALLEL-HASHMAP" "${deps.parallel-hashmap}")

        # These can be switched over to nixpkgs versions once they're updated
        # See: https://github.com/NixOS/nixpkgs/pull/428558
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-HEADERS" "${deps.opencl-headers}")
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-ICD" "${deps.opencl-icd-loader}")

        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ONEAPI-CK" "${deps.oneapi-ck}")

        # (if pkgs.stdenv.cc.isClang then throw "hiii" else "")
      ]
      # ++ lib.optionals pkgs.stdenv.cc.isClang [
      #   # (lib.cmakeFeature "CMAKE_C_FLAGS_RELEASE" "-flto=thin\\\\ -ffat-lto-objects")
      #   # (lib.cmakeFeature "CMAKE_CXX_FLAGS_RELEASE" "-flto=thin\\\\ -ffat-lto-objects")
      #   "-DCMAKE_C_FLAGS_RELEASE=-flto=thin -ffat-lto-objects"
      #   "-DCMAKE_CXX_FLAGS_RELEASE=-flto=thin -ffat-lto-objects"
      # ]
      ++ unified-runtime'.cmakeFlags;

    postPatch =
      old.postPatch
      + ''
        #   # The latter is used everywhere except this one file. For some reason,
        #   # the former is not set, at least when building with Nix, so we replace it.
        #   # See also: github.com/intel/llvm/pull/19637
        #   substituteInPlace unified-runtime/cmake/helpers.cmake \
        #     --replace-fail "PYTHON_EXECUTABLE" "Python3_EXECUTABLE"

        #   # When running without this, their CMake code copies files from the Nix store.
        #   # As the Nix store is read-only and COPY copies permissions by default,
        #   # this will lead to the copied files also being read-only.
        #   # As CMake at a later point wants to write into copied folders, this causes
        #   # the build to fail with a (rather cryptic) permission error.
        #   # By setting NO_SOURCE_PERMISSIONS we side-step this issue.
        #   # Note in case of future build failures: if there are executables in any of the copied folders,
        #   # we may need to add special handling to set the executable permissions.
        #   # See also: https://github.com/intel/llvm/issues/19635#issuecomment-3134830708
        #   sed -i '/file(COPY / { /NO_SOURCE_PERMISSIONS/! s/)\s*$/ NO_SOURCE_PERMISSIONS)/ }' \
        #     unified-runtime/cmake/FetchLevelZero.cmake \
        #     sycl/CMakeLists.txt \
        #     sycl/cmake/modules/FetchEmhash.cmake

        #   # Some libraries check for the version of the compiler.
        #   # For some reason, this version is determined by the
        #   # date of compilation. As the nix sandbox tells CMake
        #   # it's running at Unix epoch, this will always result in
        #   # a waaaay too old version.
        #   # To avoid this, we set the version to a fixed value.
        #   # See also: https://github.com/intel/llvm/issues/19692
        #   substituteInPlace sycl/CMakeLists.txt \
        #     --replace-fail 'string(TIMESTAMP __SYCL_COMPILER_VERSION "%Y%m%d")' 'set(__SYCL_COMPILER_VERSION "${date}")'

        # mkdir buildbot
        # cp ${src}/buildbot/configure.py buildbot/configure.py
      '';

    preConfigure =
      old.preConfigure
      + ''
          cmakeFlagsArray+=(
            "-DCMAKE_C_FLAGS_RELEASE=-flto=thin -ffat-lto-objects"
            "-DCMAKE_CXX_FLAGS_RELEASE=-flto=thin -ffat-lto-objects"
          )
        #   # TODO: This creates a dependency we don't want and may introduce excess recompilation
        #   flags=$(python buildbot/configure.py \
        #             --print-cmake-flags \
        #             -t Release \
        #             --docs \
        #             --cmake-gen Ninja \
        #             ${lib.optionalString cudaSupport "--cuda"} \
        #             ${lib.optionalString rocmSupport "--hip"} \
        #             ${lib.optionalString nativeCpuSupport "--native_cpu"} \
        #             ${lib.optionalString useLibcxx "--use-libcxx"} \
        #             ${lib.optionalString useLibcxx "--libcxx-include ${lib.getInclude libcxx}/include"} \
        #             ${lib.optionalString useLibcxx "--libcxx-library ${lib.getLib libcxx}/lib"} \
        #             ${lib.optionalString useLdd "--use-lld"} \
        #             ${lib.optionalString levelZeroSupport "--level_zero_adapter_version V1"} \
        #             ${lib.optionalString levelZeroSupport "--l0-headers ${lib.getInclude level-zero}/include/level_zero"} \
        #             ${lib.optionalString levelZeroSupport "--l0-loader ${lib.getLib level-zero}/lib/libze_loader.so"} \
        #             # --enable-all-llvm-targets
        #             # --shared-libs # Bad and should not be used
        #         )

        #         # We eval because flags is separated as shell-escaped strings.
        #         # We can't just split by space because it may contain escaped spaces,
        #         # so we just let bash handle it.
        #         # TODO: This may not be necessary
        #         # NOTE: We prepend, so that flags we set manually override what the build script does.
        #         eval "prependToVar cmakeFlags $flags"

        #         # Remove the install prefix flag
        #         cmakeFlags=(''${cmakeFlags[@]/-DCMAKE_INSTALL_PREFIX=\/build\/source\/build\/install})
      '';
  });
}
