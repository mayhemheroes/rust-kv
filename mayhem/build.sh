#!/usr/bin/env bash
#
# mayhem/build.sh — build rust-kv's cargo-fuzz target as a sanitized libFuzzer binary
# (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS) and build the crate's unit-test
# suite (normal flags) for mayhem/test.sh to RUN.
#
# Runs inside the commit image (RUST mayhem/Dockerfile) as `mayhem` in /mayhem.
# The Rust toolchain + cargo registry live at $CARGO_HOME=/opt/toolchains/rust/cargo.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE against
# the registry cache this first (online) build populates. Do NOT hard-code --offline.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# OSS-Fuzz Rust libFuzzer+ASan flags. rustc ignores the clang-oriented $SANITIZER_FLAGS,
# so map the ASan intent to the rustc flag (ASan is the default halting sanitizer).
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address -Cforce-frame-pointers"

# Debug-info contract (SPEC 6.2 item 10): Mayhem triage cannot read DWARF >= 4, and
# LLVM default -Cdebuginfo emits DWARF-5, so pin DWARF < 4 explicitly.
export RUST_DEBUG_FLAGS="${RUST_DEBUG_FLAGS:--Cdebuginfo=1 -Zdwarf-version=3}"
export RUSTFLAGS="$RUSTFLAGS $RUST_DEBUG_FLAGS"

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# Discover every target from the crate's fuzz_targets/ dir (one binary per target).
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

# The precompiled Rust ASan runtime archive ships DWARF-5 debug CUs from the toolchain
# build; rustc's -Zdwarf-version governs only OUR CUs, so strip debug info from the
# runtime archive so the linked binary passes the DWARF < 4 gate (SPEC 6.2 item 10).
for _asan in $(find /opt/toolchains/rust -name 'librustc-*_rt.asan.a' 2>/dev/null); do
  echo "stripping DWARF-5 debug info from runtime archive: $_asan"
  objcopy --strip-debug "$_asan" "$_asan.tmp" && mv "$_asan.tmp" "$_asan"
done

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Build the crate's OWN unit tests with NORMAL flags (clean, non-sanitized) so
# mayhem/test.sh only RUNS them. --all-features unlocks the feature-gated encoding
# tests (json/msgpack/bincode/lexpr), all of which are known-answer assert_eq! tests.
echo "=== building rust-kv test suite (normal flags, --all-features) ==="
env -u RUSTFLAGS cargo test --no-run --all-features --target-dir "$SRC/target-tests"
echo "build.sh complete"
