#!/bin/bash
# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
#
# Builds rsbridge-ios for device + simulator and packages both into
# ios/Anki.xcframework.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

source "$HOME/.cargo/env"
export PATH="/opt/homebrew/bin:$PATH"
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-26.0}"
export PROTOC="${PROTOC:-/opt/homebrew/bin/protoc}"

CFLAGS="${CFLAGS:-} -miphoneos-version-min=$IPHONEOS_DEPLOYMENT_TARGET" cargo build --release --manifest-path "$ROOT/Cargo.toml" --target aarch64-apple-ios -p rsbridge-ios
cargo build --release --manifest-path "$ROOT/Cargo.toml" --target aarch64-apple-ios-sim -p rsbridge-ios

rm -rf Anki.xcframework
xcodebuild -create-xcframework \
    -library "$ROOT/target/aarch64-apple-ios/release/librsbridge_ios.a" \
    -headers rsbridge-ios/include \
    -library "$ROOT/target/aarch64-apple-ios-sim/release/librsbridge_ios.a" \
    -headers rsbridge-ios/include \
    -output Anki.xcframework

echo "Built ios/Anki.xcframework"
