#!/bin/bash
# EpoBrowser 릴리즈: 설치 파일 만들기 → dist/latest.json 쓰기 → 깃허브에 올리기 → 구글 드라이브에 공유용 복사
# 앱의 업데이트 기능은 깃허브 dist/latest.json 을 보고 새 버전을 알려 줌
# 쓰는 법: ./release.sh "바뀐 점 1" "바뀐 점 2" ...   (버전은 Info.plist 에서 먼저 올려 둘 것)
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Info.plist)
FILE="EpoBrowser-$VERSION.pkg"

./make_pkg.sh

echo "▶ dist/latest.json 쓰는 중"
python3 - "$VERSION" "$BUILD" "$FILE" "$@" <<'EOF'
import json, sys, datetime
version, build, file, *notes = sys.argv[1:]
info = {"version": version, "build": int(build), "file": file, "notes": notes,
        "date": datetime.date.today().isoformat()}
with open("dist/latest.json", "w", encoding="utf-8") as f:
    json.dump(info, f, ensure_ascii=False, indent=2)
    f.write("\n")
EOF

# 외장하드(exFAT) 숨김 파일 정리 (.git 안까지)
find . -name '._*' -not -path './.build/*' -delete 2>/dev/null || true

echo "▶ 깃허브에 올리는 중"
git add -A
git commit -q -m "릴리즈 $VERSION" -m "$(printf '%s\n' "$@")" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -q origin main
find .git -name '._*' -delete 2>/dev/null || true

# 구글 드라이브: 공유용 (업데이트와는 상관없음)
DRIVE=$(ls -d "$HOME"/Library/CloudStorage/GoogleDrive-*/"내 드라이브" 2>/dev/null | head -1 || true)
if [ -n "$DRIVE" ]; then
    mkdir -p "$DRIVE/EpoBrowser 배포판"
    cp -X "dist/$FILE" "$DRIVE/EpoBrowser 배포판/"
    echo "▶ 구글 드라이브에 복사: $DRIVE/EpoBrowser 배포판/$FILE"
fi

echo "✅ 릴리즈 $VERSION ($BUILD) 완료"
