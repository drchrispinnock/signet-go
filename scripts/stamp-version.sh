#!/bin/sh
# Xcode build phase: stamp the built Info.plist with the version from git, after upstream's
# scripts/stamp-version.sh, but numeric as App Store Connect requires:
#   CFBundleShortVersionString = the latest tag reachable, without the leading "v", if it is
#                                1–3 dot-separated numbers (e.g. 0.2), else the project's value
#   CFBundleVersion            = number of commits on this branch (monotonic build number)
#   SignetGitDescribe          = git describe --tags --always --dirty, shown in Settings
# Falls back to whatever the project set when git is unavailable (e.g. building from a tarball).
set -eu
PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
[ -f "$PLIST" ] || exit 0
if ! git -C "$SRCROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "note: not a git checkout; leaving version as configured"
  exit 0
fi
TAG="$(git -C "$SRCROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
DESCRIBE="$(git -C "$SRCROOT" describe --tags --always --dirty 2>/dev/null | sed 's/^v//')"
BUILD="$(git -C "$SRCROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
if printf '%s' "$TAG" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TAG" "$PLIST"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :SignetGitDescribe" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SignetGitDescribe string $DESCRIBE" "$PLIST"
echo "Stamped Signet Go ${TAG:-as configured} (build $BUILD, $DESCRIBE)"
