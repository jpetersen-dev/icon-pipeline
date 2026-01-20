#!/bin/bash
set -e

# Detectar comando de ImageMagick
if command -v magick >/dev/null 2>&1; then
  IMG_TOOL="magick"
  ALPHA_KEY="alpha"
elif command -v convert >/dev/null 2>&1; then
  IMG_TOOL="convert"
  ALPHA_KEY="matte"
else
  echo "Error: ImageMagick no instalado." >&2
  exit 1
fi

mkdir -p output/design

for img in input/png/*.png; do
  [ -e "$img" ] || continue
  name=$(basename "$img" .png)
  target="output/design/${name}.svg"

  if [ -f "$target" ]; then
    echo "Saltando $name: Ya existe en design."
    continue
  fi

  echo "Procesando con compatibilidad IM6/IM7: $name..."

  # Usamos $ALPHA_KEY para que funcione en cualquier versión
  $IMG_TOOL "$img" \
    -alpha set \
    -fuzz 18% \
    -fill none \
    -draw "$ALPHA_KEY 0,0 floodfill" \
    -colorspace Gray \
    -auto-level \
    -threshold 55% \
    -morphology Close Disk:1 \
    "${name}_bn.png"

  $IMG_TOOL "${name}_bn.png" "${name}.bmp"
  potrace "${name}.bmp" -s -o "$target"
  rm "${name}_bn.png" "${name}.bmp"
done