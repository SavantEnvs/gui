#!/usr/bin/env bash
#
# mayhem/build.sh — builds Bitcoin Core's libFuzzer binary (build_fuzz/bin/fuzz -> /mayhem/fuzz, one
# harness per FUZZ=<name>, selected in each Mayhemfile) with the project itself sanitized, and the
# unit-test binary (build_tests/bin/test_bitcoin) with normal flags for mayhem/test.sh.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# The compilers come from the exported CC/CXX, not -DCMAKE_*_COMPILER: under the ccache prefill the
# first configure caches the masquerade path, and a re-run passing plain "clang" would count as a
# compiler change, wipe the cache and drop the -D options (re-run fails at the wallet/sqlite check).
# Options shared by both configurations: only the library code the harnesses and unit tests need
# (no wallet/IPC/GUI/binaries; wallet and IPC would need sqlite/capnproto and double the build time).
COMMON=(-G Ninja
        -DWITH_CCACHE=OFF -DENABLE_WALLET=OFF -DENABLE_IPC=OFF -DENABLE_EXTERNAL_SIGNER=OFF
        -DBUILD_GUI=OFF -DBUILD_GUI_TESTS=OFF -DBUILD_BENCH=OFF -DBUILD_BITCOIN_BIN=OFF -DBUILD_DAEMON=OFF
        -DBUILD_CLI=OFF -DBUILD_TX=OFF -DBUILD_UTIL=OFF -DBUILD_WALLET_TOOL=OFF -DBUILD_UTIL_CHAINSTATE=OFF
        -DBUILD_KERNEL_LIB=OFF -DINSTALL_MAN=OFF -DCMAKE_BUILD_TYPE=RelWithDebInfo
        -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld)

# 1) Sanitized fuzz binary. Upstream's BUILD_FOR_FUZZING path with SANITIZERS=fuzzer compiles the
#    libraries with -fsanitize=fuzzer-no-link (SanCov) and links the binary with -fsanitize=fuzzer.
#    -g1 + -gdwarf-3 keeps line tables (DWARF 3) so backtraces resolve source lines without the size
#    of full variable info on ~1000 template-heavy TUs.
FUZZ_BUILD="$SRC/build_fuzz"
mkdir -p "$FUZZ_BUILD"
FUZZ_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -g1 -ftrivial-auto-var-init=pattern"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -g1 -c "$SRC/mayhem/fuzz_runtime.cc" -o "$FUZZ_BUILD/fuzz_runtime.o"
cmake -S . -B "$FUZZ_BUILD" "${COMMON[@]}" \
  -DBUILD_FOR_FUZZING=ON -DSANITIZERS=fuzzer \
  -DCMAKE_C_FLAGS="$FUZZ_CFLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_CFLAGS" \
  -DCMAKE_C_FLAGS_RELWITHDEBINFO=-O1 -DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-O1 \
  -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld $FUZZ_BUILD/fuzz_runtime.o"
cmake --build "$FUZZ_BUILD" --target fuzz -j"$MAYHEM_JOBS"
install -m 0755 "$FUZZ_BUILD/bin/fuzz" "$SRC/fuzz"

# 2) Unit-test binary with the project's normal flags (no sanitizers, no fuzzing) for mayhem/test.sh.
TEST_BUILD="$SRC/build_tests"
mkdir -p "$TEST_BUILD"
cmake -S . -B "$TEST_BUILD" "${COMMON[@]}" \
  -DBUILD_TESTS=ON -DBUILD_FUZZ_BINARY=OFF \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_C_FLAGS_RELWITHDEBINFO=-O2 -DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-O1
cmake --build "$TEST_BUILD" --target test_bitcoin -j"$MAYHEM_JOBS"
