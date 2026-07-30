#!/bin/bash
# Runs the test suite. With Command Line Tools only, Testing.framework and
# lib_TestingInterop live outside the default search paths, so we add them.
set -euo pipefail
cd "$(dirname "$0")/.."
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [ -d "$FW" ]; then
  swift test \
    -Xswiftc -F"$FW" \
    -Xlinker -F"$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" "$@"
else
  swift test "$@"
fi
