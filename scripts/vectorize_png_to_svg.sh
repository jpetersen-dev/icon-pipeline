#!/bin/bash
set -e

# Detectar comando de ImageMagick (magick o convert)
if command -v magick >/dev/null 2>&1; then
  IMG_TOOL="magick"
elif command -v convert >/dev/null 2>&1; then
  IMG_TOOL="convert"
else
  echo "Error: ImageMagick no instalado." >&2
  exit 1
fi

mkdir -p output/design

for img in input/png/*.png; do
  [ -e "$img" ] || continue
  name=$(basename "$img" .png)
  target="output/design/${name}.svg"

  # EFICIENCIA: Solo procesar si el SVG no existe
  if [ -f "$target" ]; then
    echo "Saltando $name: Ya existe en design."
    continue
  fi

  echo "Vectorizando: $name..."

  $IMG_TOOL "$img" \
    -alpha set -fuzz 15% -fill none -draw "color 0,0 floodfill" \
    -colorspace Gray -threshold 50% -morphology Dilate Diamond:1 \
    "${name}_bn.png"

  $IMG_TOOL "${name}_bn.png" "${name}.bmp"
  potrace "${name}.bmp" -s -o "$target"
  rm "${name}_bn.png" "${name}.bmp"
done