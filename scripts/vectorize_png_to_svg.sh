#!/bin/bash
set -e

# Detectar comando de ImageMagick
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

  # Solo procesar si no existe el SVG
  if [ -f "$target" ]; then
    echo "Saltando $name: Ya existe en design."
    continue
  fi

  echo "Procesando con pipeline refinado: $name..."

  # Aplicando tus parámetros de éxito local
  $IMG_TOOL "$img" \
    -alpha set \
    -fuzz 18% \
    -fill none \
    -draw "alpha 0,0 floodfill" \
    -colorspace Gray \
    -auto-level \
    -threshold 55% \
    -morphology Close Disk:1 \
    "${name}_bn.png"

  $IMG_TOOL "${name}_bn.png" "${name}.bmp"
  
  # Potrace convierte el BMP (negro sobre transparente/blanco) en trazado puro
  potrace "${name}.bmp" -s -o "$target"
  
  rm "${name}_bn.png" "${name}.bmp"
done