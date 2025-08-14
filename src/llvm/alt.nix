{
  lib,
  cmake,
  parallel-hashmap,
  ninja,
  llvmPackages_21,
  callPackage,
  fetchFromGitHub,
  runCommand,
  zlib,
  zstd,
  unified-runtime,
  hwloc,
  spirv-headers,
  spirv-tools,
  spirv-llvm-translator,
  vc-intrinsics,
  emhash,
  libedit,
  tree,
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
  useLld ? true,
  buildTests ? false,
  buildDocs ? false,
  buildMan ? false,
}: let
  version = "unstable-2025-08-14";
  date = "20250814";
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
  srcOrig = fetchFromGitHub {
    owner = "intel";
    repo = "llvm";
    # tag = "sycl-web/sycl-latest-good";
    rev = "8959a5e5a6cebac8993c58c5597638b4510be91f";
    hash = "sha256-W+TpIeWlpkYpPI43lzI2J3mIIkzb9RtNTKy/0iQHyYI=";
  };
  src = runCommand "intel-llvm-src-fixed-${version}" {} ''
    cp -r ${srcOrig} $out
    chmod -R u+w $out

    # The latter is used everywhere except this one file. For some reason,
    # the former is not set, at least when building with Nix, so we replace it.
    # See also: github.com/intel/llvm/pull/19637
    substituteInPlace $out/unified-runtime/cmake/helpers.cmake \
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
    # sed -i '/file(COPY / { /NO_SOURCE_PERMISSIONS/! s/)\s*$/ NO_SOURCE_PERMISSIONS)/ }' \
    #   $out/unified-runtime/cmake/FetchLevelZero.cmake
      #$out/sycl/CMakeLists.txt \
      #$out/sycl/cmake/modules/FetchEmhash.cmake \

    # Parts of libdevice are built using the freshly-built compiler.
    # As it tries to link to system libraries, we need to wrap it with the
    # usual nix cc-wrapper.
    # Since the compiler to be wrapped is not available at this point,
    # we use a stub that points to where it will be later on
    # in `/build/source/build/bin/clang-21`
    # Note: both nix and bash try to expand clang_exe here, so double-escape it
    #substituteInPlace libdevice/cmake/modules/SYCLLibdevice.cmake \
    #  --replace-fail "\''${clang_exe}" "$ {ccWrapperStub}/bin/clang++"

    # Some libraries check for the version of the compiler.
    # For some reason, this version is determined by the
    # date of compilation. As the nix sandbox tells CMake
    # it's running at Unix epoch, this will always result in
    # a waaaay too old version.
    # To avoid this, we set the version to a fixed value.
    # See also: https://github.com/intel/llvm/issues/19692
    substituteInPlace $out/sycl/CMakeLists.txt \
      --replace-fail 'string(TIMESTAMP __SYCL_COMPILER_VERSION "%Y%m%d")' 'set(__SYCL_COMPILER_VERSION "${date}")'
  '';
  llvmPackages = llvmPackages_21;
  # TODO: I'm not sure whether we need to override the src, or if
  # they just vendored upstream without patches.
  spirv-llvm-translator' =
    (spirv-llvm-translator.override {
      inherit (llvmPackages) llvm;
    }).overrideAttrs
    (old: {
      src = runCommand "spirv-llvm-translator-src-${version}" {} ''
        cp -r ${src}/llvm-spirv $out
      '';
    });
  tblgen = pkgs.tblgen.overrideAttrs (old: {
    buildInputs = (old.buildInputs or []) ++ [vc-intrinsics];
  });
  stdenv =
    if useLibcxx
    then llvmPackages.libcxxStdenv
    else llvmPackages.stdenv;
  pkgs = llvmPackages.override (old: {
    inherit stdenv;
    #inherit src;

    version = "21.0.0-${srcOrig.rev}";

    officialRelease = {};

    monorepoSrc = src;

    doCheck = false;

    # enableSharedLibraries = false;

    buildLlvmTools.tblgen = tblgen;
  });
in
  pkgs
  // rec {
    inherit tblgen;
    llvm = pkgs.llvm.overrideAttrs (
      old: let
        src' = runCommand "llvm-src-${version}" {inherit (src) passthru;} ''
          mkdir -p "$out"
          cp -r ${src}/llvm "$out"
          cp -r ${src}/cmake "$out"
          cp -r ${src}/third-party "$out"
          cp -r ${src}/libc "$out"

          cp -r ${src}/sycl "$out"
          cp -r ${src}/sycl-jit "$out"
          cp -r ${src}/llvm-spirv "$out"
          # cp -r ${src}/unified-runtime "$out"

          chmod u+w "$out/llvm/tools"
          cp -r ${src}/polly "$out/llvm/tools"

          # chmod u+w "$out/llvm/projects"
          # cp -r ${vc-intrinsics.src} "$out/llvm/projects"
        '';
      in {
        # inherit src;
        src = src';

        nativeBuildInputs =
          old.nativeBuildInputs
          ++ lib.optionals useLld [
            llvmPackages_21.bintools
          ];

        buildInputs =
          old.buildInputs
          ++ [
            stdenv.cc.cc.lib
            zstd

            emhash

            libedit
            # zlib
            # hwloc

            # spirv-llvm-translator'

            # vc-intrinsics

            # Not sure if this is needed
            # spirv-llvm-translator'
            # intel-compute-runtime

            # For libspirv_dis
            spirv-tools
          ]
          ++ unified-runtime'.buildInputs;

        propagatedBuildInputs = [
          zlib
          hwloc
        ];

        doCheck = false;

        cmakeFlags =
          old.cmakeFlags
          ++ [
            "-DCMAKE_BUILD_TYPE=Release"
            "-DLLVM_ENABLE_ZSTD=FORCE_ON"
            "-DLLVM_ENABLE_ZLIB=FORCE_ON"
            "-DLLVM_ENABLE_THREADS=ON"
            "-DLLVM_ENABLE_LTO=Thin"

            (lib.cmakeBool "BUILD_SHARED_LIBS" false)
            # TODO: configure fails when these are true, but I've no idea why
            # NOTE: Fails with buildbot/configure.py as well when these are set
            (lib.cmakeBool "LLVM_LINK_LLVM_DYLIB" false)
            (lib.cmakeBool "LLVM_BUILD_LLVM_DYLIB" false)

            # (lib.cmakeBool "LLVM_ENABLE_LIBCXX" useLibcxx)
            # (lib.cmakeFeature "CLANG_DEFAULT_CXX_STDLIB" (if useLibcxx then "libc++" else "libstdc++"))

            (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
            (lib.cmakeBool "FETCHCONTENT_QUIET" false)

            # (lib.cmakeFeature "LLVMGenXIntrinsics_SOURCE_DIR" "${deps.vc-intrinsics}")
            (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_VC-INTRINSICS" "${deps.vc-intrinsics}")

            (lib.cmakeFeature "LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR" "${spirv-headers.src}")

            # (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_EMHASH" "${deps.emhash}")
            # (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_PARALLEL-HASHMAP" "${deps.parallel-hashmap}")

            # These can be switched over to nixpkgs versions once they're updated
            # See: https://github.com/NixOS/nixpkgs/pull/428558
            (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-HEADERS" "${deps.opencl-headers}")
            (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-ICD" "${deps.opencl-icd-loader}")

            (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ONEAPI-CK" "${deps.oneapi-ck}")

            # "-DLLVM_EXTERNAL_VC_INTRINSICS_SOURCE_DIR=${vc-intrinsics.src}"
            #"-DLLVM_EXTERNAL_PROJECTS=sycl;llvm-spirv;opencl;xpti;xptifw;libdevice;sycl-jit"
            # "-DLLVM_EXTERNAL_PROJECTS=sycl;llvm-spirv"
            "-DLLVM_EXTERNAL_PROJECTS=llvm-spirv"
            # "-DLLVM_EXTERNAL_SYCL_SOURCE_DIR=/build/${src'.name}/sycl"
            "-DLLVM_EXTERNAL_LLVM_SPIRV_SOURCE_DIR=/build/${src'.name}/llvm-spirv"
            #"-DLLVM_EXTERNAL_XPTI_SOURCE_DIR=/build/${src'.name}/xpti"
            #"-DXPTI_SOURCE_DIR=/build/${src'.name}/xpti"
            #"-DLLVM_EXTERNAL_XPTIFW_SOURCE_DIR=/build/${src'.name}/xptifw"
            #"-DLLVM_EXTERNAL_LIBDEVICE_SOURCE_DIR=/build/${src'.name}/libdevice"
            # "-DLLVM_EXTERNAL_SYCL_JIT_SOURCE_DIR=/build/${src'.name}/sycl-jit"
            #"-DLLVM_ENABLE_PROJECTS=clang\;sycl\;llvm-spirv\;opencl\;xpti\;xptifw\;libdevice\;sycl-jit\;libclc\;lld"
            # "-DLLVM_ENABLE_PROJECTS=llvm-spirv"

            # These require clang, which we don't have at this point.
            # TODO: Build these later, e.g. in passthru.tests
            "-DLLVM_SPIRV_INCLUDE_TESTS=OFF"

            "-DLLVM_SPIRV_ENABLE_LIBSPIRV_DIS=ON"

            # (if pkgs.stdenv.cc.isClang then throw "hiii" else "")
          ]
          # ++ lib.optionals pkgs.stdenv.cc.isClang [
          #   # (lib.cmakeFeature "CMAKE_C_FLAGS_RELEASE" "-flto=thin\\\\ -ffat-lto-objects")
          #   # (lib.cmakeFeature "CMAKE_CXX_FLAGS_RELEASE" "-flto=thin\\\\ -ffat-lto-objects")
          #   "-DCMAKE_C_FLAGS_RELEASE=-flto=thin -ffat-lto-objects"
          #   "-DCMAKE_CXX_FLAGS_RELEASE=-flto=thin -ffat-lto-objects"
          # ]
          ++ lib.optional useLld (lib.cmakeFeature "LLVM_USE_LINKER" "lld")
          ++ unified-runtime'.cmakeFlags
          # ++ ["-DUR_ENABLE_TRACING=OFF"]
          ;

        preConfigure =
          old.preConfigure
          + ''
            cmakeFlagsArray+=(
              "-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG -march=skylake -mtune=znver3 -flto=thin -ffat-lto-objects"
              "-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -march=skylake -mtune=znver3 -flto=thin -ffat-lto-objects"
            )
          '';

        postInstall =
          ''
            # Check if the rogue include directory was created in $out
            if [ -d $out/include ]; then
              # Move its contents to the correct destination

              echo "searchmarker 123123123"
              ls $out/include
              ${tree}/bin/tree $out
              echo ------------
              ls $dev/include
              echo ------------

              mv $out/include/LLVMSPIRVLib $dev/include/
              mv $out/include/llvm/ExecutionEngine $dev/include/llvm/ExecutionEngine/
              mv $out/include/llvm/SYCLLowerIR $dev/include/llvm/SYCLLowerIR/
              # mv $out/include/llvm/* $dev/include/llvm
              # Remove the now-empty directory so fixupPhase doesn't see it
              rmdir $out/include
            fi
          ''
          + (old.postInstall or "");
        #
        # preFixup = old.preFixup + ''
        #   ls
        # '';
      }
    );

    xpti = stdenv.mkDerivation (finalAttrs: {
      pname = "xpti";
      inherit version;

      src = runCommand "xpti-src-${version}" {inherit (src) passthru;} ''
        mkdir -p "$out"
        cp -r ${src}/xpti "$out"
      '';

      sourceRoot = "${finalAttrs.src.name}/xpti";

      nativeBuildInputs = [
        cmake
        ninja
      ];
    });

    xptifw = stdenv.mkDerivation (finalAttrs: {
      pname = "xptifw";
      inherit version;

      src = runCommand "xptifw-src-${version}" {inherit (src) passthru;} ''
        mkdir -p "$out"
        cp -r ${src}/xptifw "$out"

        mkdir -p "$out/sycl/cmake/modules"
        cp -r ${src}/sycl/cmake/modules/FetchEmhash.cmake "$out/sycl/cmake/modules"
      '';

      sourceRoot = "${finalAttrs.src.name}/xptifw";

      nativeBuildInputs = [
        cmake
        ninja
      ];

      buildInputs = [
        parallel-hashmap
        xpti
      ];

      # TODO
      cmakeFlags = [
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_EMHASH" "${deps.emhash}")
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_PARALLEL-HASHMAP" "${parallel-hashmap.src}")
      ];
    });
  }
