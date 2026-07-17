#!/bin/bash
# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
#
# Generates Swift protobuf messages for all of proto/anki/ into
# ios/AnkiApp/Generated/. We compile the whole folder rather than curating
# an exact subset of the ~12 v1 RPCs: the proto files cross-import each
# other heavily, and protoc/protoc-gen-swift are fast enough that this is
# the simplest correct option.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
OUT="AnkiApp/Generated"

export PATH="/opt/homebrew/bin:$PATH"

rm -rf "$OUT"
mkdir -p "$OUT"

protoc \
    -I "$ROOT/proto" \
    --swift_out="$OUT" \
    --swift_opt=Visibility=Public \
    "$ROOT"/proto/anki/*.proto

echo "Generated $(ls "$OUT" | wc -l | tr -d ' ') Swift files in ios/$OUT"
