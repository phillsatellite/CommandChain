#!/usr/bin/env bash
# Runs the unit tests. With full Xcode this is just `swift test`; with only the
# Command Line Tools installed, the Swift Testing framework needs explicit search paths.
set -euo pipefail
cd "$(dirname "$0")/.."

CLT=/Library/Developer/CommandLineTools/Library/Developer
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools* && -d "$CLT/Frameworks/Testing.framework" ]]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
    -Xlinker -F -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/usr/lib" \
    "$@"
fi
exec swift test "$@"
