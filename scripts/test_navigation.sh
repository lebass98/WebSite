#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_WORK=$(mktemp -d /tmp/epo-navigation.XXXXXX)
trap 'rm -rf "$TEST_WORK"' EXIT
swiftc -parse-as-library Sources/EpoBrowser/Navigation.swift Sources/EpoBrowser/Filters.swift Tests/NavigationRegression.swift -o "$TEST_WORK/navigation-tests"
"$TEST_WORK/navigation-tests"
