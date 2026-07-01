#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the kv crate's OWN unit tests (built by mayhem/build.sh with
# normal flags into $SRC/target-tests). These are known-answer tests: they set a value
# then assert_eq! the value read back (and check config/encoding round-trips) — a real
# behavioral oracle, so a PATCH that neuters the code to exit(0) FAILS here. Emits CTRF.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# The suite was compiled by build.sh; re-using the same target dir just re-links and
# executes (no recompile of the project). Fail loudly if it was never built.
if [ ! -d "$SRC/target-tests" ]; then
  echo "ERROR: $SRC/target-tests missing — mayhem/build.sh did not build the test suite" >&2
  emit_ctrf "cargo-test" 0 1
  exit 1
fi

# --test-threads=1: the tests share on-disk sled paths under ./test/, so run serially.
out="$(env -u RUSTFLAGS cargo test --all-features --target-dir "$SRC/target-tests" -- --test-threads=1 2>&1)"
status=$?
echo "$out"

read -r passed failed ignored < <(printf '%s\n' "$out" | awk '
  /^test result:/ {
    for (i = 1; i <= NF; i++) {
      if ($i == "passed;")  p += $(i-1);
      if ($i == "failed;")  f += $(i-1);
      if ($i == "ignored;") g += $(i-1);
    }
  }
  END { printf "%d %d %d", p, f, g }')
passed=${passed:-0}; failed=${failed:-0}; ignored=${ignored:-0}

if [ "$status" -ne 0 ] && [ "$failed" -eq 0 ] && [ "$passed" -eq 0 ]; then
  failed=1
fi
if [ "$passed" -eq 0 ] && [ "$failed" -eq 0 ]; then
  echo "ERROR: no test result lines parsed — suite did not run" >&2
  failed=1
fi

emit_ctrf "cargo-test" "$passed" "$failed" "$ignored"
