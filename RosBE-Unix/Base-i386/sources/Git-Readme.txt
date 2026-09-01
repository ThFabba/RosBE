The source archives in this directory are not stored in Git.

Run ../fetch-sources.sh to download, verify, and prepare all source archives
automatically.  See ../AGENTS.md for full documentation.

If you prefer to prepare the archives manually, each .tar.bz2 file must
contain the tool's source tree in a subdirectory named as follows:

- binutils.tar.bz2   --> subdirectory "binutils"   (Binutils source)
- bison.tar.bz2      --> subdirectory "bison"       (Bison source, patched)
- cmake.tar.bz2      --> subdirectory "cmake"       (ReactOS CMake fork, unpatched in the archive)
- flex.tar.bz2       --> subdirectory "flex"        (Flex source, after make dist)
- gcc.tar.bz2        --> subdirectory "gcc"         (GCC source)
- gmp.tar.bz2        --> subdirectory "gmp"         (GMP source, patched)
- mingw_w64.tar.bz2  --> subdirectory "mingw_w64"   (mingw-w64 source)
- mpc.tar.bz2        --> subdirectory "mpc"         (MPC source)
- mpfr.tar.bz2       --> subdirectory "mpfr"        (MPFR source)
- ninja.tar.bz2      --> subdirectory "ninja"       (Ninja source)
