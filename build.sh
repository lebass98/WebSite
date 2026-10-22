#!/bin/bash
# EpoBrowser 테스트용 빌드 → ~/Library/Caches/EpoBrowser-test/EpoBrowser.app 생성
# (외장하드가 exFAT이라 앱 서명이 안 될 수 있어서, 앱은 내장 디스크에 만듦)
# 테스트 앱은 휴지통에 버리지 말 것: 정리 앱(CleanMyMac)이 "남은 파일"이라며
# 진짜 앱의 데이터(~/Library/Application Support/EpoBrowser, 설정)까지 지울 수 있음.
# 다음 빌드 때 이 자리에서 덮어쓰니 그냥 두면 됨.
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ 빌드 중..."
swift build -c release

APP="$HOME/Library/Caches/EpoBrowser-test/EpoBrowser.app"
echo "▶ 앱 묶는 중: $APP"
pkill -x EpoBrowser 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/EpoBrowser "$APP/Contents/MacOS/EpoBrowser"
cp Info.plist "$APP/Contents/Info.plist"
# 아이콘이 있을 때만 넣음 (scripts/make_icon.swift로 만듦)
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▶ 서명 중 (내 Mac 전용)"
# 개인용 서명 (다시 빌드하면 macOS가 새 앱으로 보고 권한을 다시 요청함)
codesign --force --sign - "$APP"

echo "✅ 완료: $APP"

echo "▶ 앱 실행"
open "$APP"
