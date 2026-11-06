#!/usr/bin/env bash
#
# mayhem/test.sh — RUNS Bitcoin Core's own Boost unit tests (test_bitcoin, built by mayhem/build.sh with
# normal flags) for the parsing/serialization/script/crypto suites the fuzz targets exercise. The
# pass/fail counts come from the suites' own known-answer assertions as reported by Boost.Test.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
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

BIN="$SRC/build_tests/bin/test_bitcoin"
if [ ! -x "$BIN" ]; then
  echo "test.sh: $BIN missing (mayhem/build.sh should have built it)" >&2
  emit_ctrf "boost-test" 0 1 0
  exit $?
fi

SUITES="hash_tests,base58_tests,base32_tests,base64_tests,bech32_tests,key_io_tests,key_tests,uint256_tests,arith_uint256_tests,serialize_tests,merkle_tests,pmt_tests,transaction_tests,script_tests,scriptnum_tests,script_parse_tests,script_standard_tests,sighash_tests,descriptor_tests,miniscript_tests,psbt_tests,blockfilter_tests,bloom_tests,netbase_tests,addrman_tests,crypto_tests,streams_tests,util_tests"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
"$BIN" --run_test="$SUITES" --color_output=no --log_level=test_suite --report_level=short >"$out" 2>&1
rc=$?
cat "$out"

# Boost.Test's own report: "Running N test cases...", one "Entering test case" per case, and
# "Test module ... has passed with: ... assertions out of A passed". A neutered binary prints none of it.
ran=$(sed -n 's/^Running \([0-9]\+\) test cases\?\.\.\./\1/p' "$out" | tail -n1)
entered=$(grep -c 'Entering test case "' "$out" || true)
asserts=$(sed -n 's/^ *\([0-9]\+\) assertions out of [0-9]\+ passed/\1/p' "$out" | tail -n1)
if [ -z "$ran" ] || [ "$ran" -eq 0 ] || [ "$entered" -ne "$ran" ] || [ -z "$asserts" ] || [ "$asserts" -lt 1000 ]; then
  echo "test.sh: Boost.Test reported no coherent run (ran='${ran:-}', entered=$entered, assertions='${asserts:-}')" >&2
  emit_ctrf "boost-test" 0 1 0
  exit $?
fi
failed_cases=$(grep -c 'error: in "' "$out" || true)
if [ "$rc" -ne 0 ] && [ "$failed_cases" -eq 0 ]; then failed_cases=1; fi
passed=$(( ran - failed_cases )); [ "$passed" -ge 0 ] || passed=0
emit_ctrf "boost-test" "$passed" "$failed_cases" 0
