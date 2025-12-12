{
  stdenv,
  writeTextFile,
}: {
  # Basic SYCL compilation test
  sycl-compile = stdenv.mkDerivation {
    name = "intel-llvm-test-sycl-compile";

    src = writeTextFile {
      name = "test.cpp";
      text = ''
        #include <sycl/sycl.hpp>
        #include <iostream>

        int main() {
          sycl::queue q;
          std::cout << "SYCL queue created successfully" << std::endl;
          return 0;
        }
      '';
    };

    dontUnpack = true;

    buildPhase = ''
      echo "Testing SYCL compilation..."
      clang++ -fsycl $src -o test
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp test $out/bin/sycl-test

      # Create a marker file indicating test passed
      echo "SYCL compilation test passed" > $out/test-passed
    '';

    hardeningDisable = ["zerocallusedregs" "pacret"];

    meta = {
      description = "Test that intel-llvm can compile SYCL programs";
    };
  };

  # Test that the compiler can find its own headers
  headers-available = stdenv.mkDerivation {
    name = "intel-llvm-test-headers";

    dontUnpack = true;

    buildPhase = ''
      echo "Testing header availability..."
      echo '#include <sycl/sycl.hpp>' | clang++ -fsycl -x c++ -E - > /dev/null
      echo '#include <CL/sycl.hpp>' | clang++ -fsycl -x c++ -E - > /dev/null
    '';

    installPhase = ''
      mkdir -p $out
      echo "Header availability test passed" > $out/test-passed
    '';

    hardeningDisable = ["zerocallusedregs" "pacret"];

    meta = {
      description = "Test that intel-llvm headers are accessible";
    };
  };
}
