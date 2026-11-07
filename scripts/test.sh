#!/bin/bash
# Compiles Tavra's logic, the part that touches nothing on the Mac, with Tests/CoreTests.swift and runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swiftc -swift-version 6 -parse-as-library -O -o "$OUT/core-tests" Tavra/Core/*.swift Tests/CoreTests.swift
"$OUT/core-tests"
