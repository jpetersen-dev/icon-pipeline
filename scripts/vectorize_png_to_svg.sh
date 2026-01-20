#!/bin/bash
set -e

# Detectar comando disponible de ImageMagick
if command -v magick >/dev/null 2>&1; then
  IMG_TOOL="magick"
elif command -v convert >/dev/null 2>&1; then
  IMG_TOOL="convert"
else
  echo "Error: ImageMagick no está instalado." >&2
  exit 1
fi

mkdir -p output/design

for img in input/png/*.png; do
  [ -e "$img" ] || continue
  name=$(basename "$img" .png)

  echo "Procesando: $name"

  # Generar versión B/N preparada para potrace
  $IMG_TOOL "$img" \
    -alpha set \
    -fuzz 15% \
    -fill none \
    -draw "color 0,0 floodfill" \
    -colorspace Gray \
    -threshold 50% \
    -morphology Dilate Diamond:1 \
    "${name}_bn.png"

  $IMG_TOOL "${name}_bn.png" "${name}.bmp"

  # Vectorizar
  potrace "${name}.bmp" -s -o "output/design/${name}.svg"

  # Limpieza de temporales
  rm "${name}_bn.png" "${name}.bmp"
done