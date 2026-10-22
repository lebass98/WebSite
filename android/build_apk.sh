#!/bin/bash
# 안드로이드 APK 빌드 → ../dist/EpoBrowser-<버전>.apk
# 외장하드(exFAT)의 ._ 숨김 파일이 리소스 빌드를 깨뜨려서, 내장 디스크에 복사해 빌드함
set -euo pipefail
cd "$(dirname "$0")"
SRC="$(pwd)"
WORK="$HOME/Library/Caches/EpoBrowserAndroid"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"

echo "▶ 내장 디스크로 복사: $WORK"
mkdir -p "$WORK"
COPYFILE_DISABLE=1 rsync -a --delete --exclude '._*' --exclude '.DS_Store' --exclude '.gradle' --exclude 'build' --exclude 'app/build' "$SRC/" "$WORK/"
echo "sdk.dir=$ANDROID_HOME" > "$WORK/local.properties"

cd "$WORK"
if [ ! -x ./gradlew ]; then
    echo "▶ Gradle 래퍼 만드는 중"
    gradle wrapper --gradle-version 8.11.1 -q
fi
echo "▶ APK 빌드 중"
./gradlew --no-daemon -q assembleRelease

VERSION=$(grep -m1 'versionName' app/build.gradle.kts | sed 's/.*"\(.*\)".*/\1/')
mkdir -p "$SRC/../dist"
rm -f "$SRC/../dist/"EpoBrowser-*.apk
cp app/build/outputs/apk/release/app-release.apk "$SRC/../dist/EpoBrowser-$VERSION.apk"
echo "✅ 완료: $(cd "$SRC/../dist" && pwd)/EpoBrowser-$VERSION.apk"
