#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/zfh-tests.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT

export ZFH_TEST_ROOT="$TEST_ROOT"

for test_file in "$SCRIPT_DIR"/*.test.zsh; do
  [[ $test_file == *'/run.zsh' ]] && continue
  print -- "==> ${test_file:t}"
  zsh "$test_file"
done

print -- 'All tests passed.'
