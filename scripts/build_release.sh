#!/bin/bash
set -e

cd "$(dirname "$0")/.."

VERSION=$(grep "^version:" pubspec.yaml | awk '{print $2}')
OUTDIR="build/v${VERSION}"
APPNAME="Flaming Cherubim"

echo "=============================="
echo " Building ${APPNAME} v${VERSION}"
echo "=============================="

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

echo ""
echo "[1/5] Updating dependencies..."
flutter pub get

echo ""
echo "[2/5] Building Android APKs (split per ABI)..."
flutter build apk --release --split-per-abi

# Copy and rename split APKs
for apk in build/app/outputs/flutter-apk/app-*-release.apk; do
    base=$(basename "$apk")
    # app-arm64-v8a-release.apk -> flaming-cherubim-v0.0.10-arm64-v8a.apk
    arch=$(echo "$base" | sed 's/app-//; s/-release.apk//')
    newname="flaming-cherubim-v${VERSION}-${arch}.apk"
    cp "$apk" "$OUTDIR/$newname"
    echo "  -> $newname ($(du -h "$apk" | awk '{print $1}'))"
done

echo ""
echo "[3/5] Building Android universal APK..."
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "$OUTDIR/flaming-cherubim-v${VERSION}-universal.apk"
echo "  -> flaming-cherubim-v${VERSION}-universal.apk ($(du -h build/app/outputs/flutter-apk/app-release.apk | awk '{print $1}'))"

echo ""
echo "[4/5] Building macOS app..."
flutter build macos --release
APP="build/macos/Build/Products/Release/${APPNAME}.app"
ZIPNAME="Flaming_Cherubim-v${VERSION}-mac.app.zip"
cd "$(dirname "$APP")"
ditto -c -k --sequesterRsrc --keepParent "${APPNAME}.app" "$OLDPWD/$OUTDIR/$ZIPNAME"
cd "$OLDPWD"
echo "  -> $ZIPNAME ($(du -h "$OUTDIR/$ZIPNAME" | awk '{print $1}'))"

echo ""
echo "[5/5] Generating SHA256 checksums..."
cd "$OUTDIR"
for f in *; do
    shasum -a 256 "$f" > "$f.sha256"
    echo "  $f: $(cat "$f.sha256" | awk '{print $1}')"
done
cd "$OLDPWD"

echo ""
echo "=============================="
echo " Done! Files in $OUTDIR/"
echo "=============================="
ls -lh "$OUTDIR"
