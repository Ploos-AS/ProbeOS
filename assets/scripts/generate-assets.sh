#!/bin/sh
set -e

# ProbeOS asset generator
# https://probeos.eu
# © 2026 Ploos AS

LOGO="assets/logo/logo.png"
OUTDIR="assets/generated"

mkdir -p "$OUTDIR"

WALLPAPER_W=1920
WALLPAPER_H=1080

SPLASH_W=1024
SPLASH_H=768

BG_COLOR="#0f1115"
FG_COLOR="#cfd3dc"

echo "[*] Generating wallpaper"

convert -size ${WALLPAPER_W}x${WALLPAPER_H} \
    gradient:"#141821-#0b0d12" \
    "$OUTDIR/wallpaper_base.png"

convert "$LOGO" \
    -resize 240x240 \
    "$OUTDIR/logo_scaled.png"

convert "$OUTDIR/wallpaper_base.png" \
    "$OUTDIR/logo_scaled.png" \
    -gravity southeast -geometry +80+80 \
    -composite \
    -fill "$FG_COLOR" \
    -gravity southeast \
    -pointsize 14 \
    -annotate +80+40 "ProbeOS\nhttps://probeos.eu\n© 2026 Ploos AS" \
    "$OUTDIR/wallpaper.png"

rm "$OUTDIR/wallpaper_base.png" "$OUTDIR/logo_scaled.png"

echo "[*] Generating splash screen"

convert -size ${SPLASH_W}x${SPLASH_H} xc:black \
    "$OUTDIR/splash_base.png"

convert "$LOGO" \
    -resize 320x320 \
    "$OUTDIR/logo_splash.png"

convert "$OUTDIR/splash_base.png" \
    "$OUTDIR/logo_splash.png" \
    -gravity center \
    -composite \
    -fill "$FG_COLOR" \
    -gravity south \
    -pointsize 18 \
    -annotate +0+80 "ProbeOS\nProbing hardware…" \
    "$OUTDIR/splash.png"

rm "$OUTDIR/splash_base.png" "$OUTDIR/logo_splash.png"

echo "[✓] Assets generated:"
echo " - $OUTDIR/wallpaper.png"
echo " - $OUTDIR/splash.png"
