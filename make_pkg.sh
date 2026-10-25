#!/bin/bash
# EpoBrowser 설치 파일 만들기 → dist/EpoBrowser-<버전>.pkg
# 설치하면 /Applications/EpoBrowser.app 에 들어가고 자동 실행됨
set -euo pipefail
# ._ 숨김 파일이 설치 파일에 섞이지 않게 함
export COPYFILE_DISABLE=1
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
IDENTIFIER=com.local.EpoBrowser

echo "▶ 빌드 중..."
swift build -c release

# 외장하드(exFAT)는 숨김 파일(._*)이 생겨서, 내장 디스크 임시 폴더에서 작업
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/root"
APP="$ROOT/Applications/EpoBrowser.app"

echo "▶ 앱 묶는 중"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WORK/scripts"
cp .build/release/EpoBrowser "$APP/Contents/MacOS/EpoBrowser"
cp Info.plist "$APP/Contents/Info.plist"
# 아이콘이 있을 때만 넣음 (scripts/make_icon.swift로 만듦)
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp scripts/postinstall "$WORK/scripts/postinstall"
chmod 755 "$WORK/scripts/postinstall"
# 외장하드(exFAT)는 모든 파일이 rwx------ 라서, 설치 후 사용자가 못 읽는 문제 방지
# (폴더·실행 파일 755, 나머지 644)
chmod -R u=rwX,go=rX "$ROOT"
chmod 755 "$APP/Contents/MacOS/EpoBrowser"
xattr -cr "$ROOT"
# 개인용 서명 (다시 빌드하면 macOS가 새 앱으로 보고 권한을 다시 요청함)
codesign --force --sign - "$APP"
xattr -cr "$ROOT"

# 같은 앱이 다른 위치(~/Applications 등)에 있어도 항상 /Applications 에 설치되게 함
pkgbuild --analyze --root "$ROOT" "$WORK/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$WORK/component.plist"

echo "▶ 설치 파일 만드는 중"
# macOS 27의 pkgbuild는 항상 "write: Permission denied"를 출력함 (결과물엔 영향 없음) → 그 줄만 숨김
pkgbuild --root "$ROOT" \
         --component-plist "$WORK/component.plist" \
         --scripts "$WORK/scripts" \
         --identifier "$IDENTIFIER" \
         --version "$VERSION" \
         --install-location / \
         "$WORK/component.pkg" >/dev/null 2>"$WORK/pkgbuild.err" || { cat "$WORK/pkgbuild.err" >&2; exit 1; }
grep -v '^write: Permission denied$' "$WORK/pkgbuild.err" >&2 || true

productbuild --package "$WORK/component.pkg" "$WORK/final.pkg" >/dev/null

# 완성된 파일만 외장하드로 복사 (확장 속성은 빼고)
mkdir -p dist
OUT="dist/EpoBrowser-$VERSION.pkg"
rm -f "$OUT"
cp -X "$WORK/final.pkg" "$OUT"

# 이전 배포 파일은 보존한다. 업데이트 피드는 latest.json에서 최신 버전을 선택한다.

echo "✅ 완료: $(pwd)/$OUT"
