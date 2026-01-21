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

for img in input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS}; do
  [ -e "$img" ] || continue
  
  filename=$(basename -- "$img")
  name="${filename%.*}"
  target="output/design/${name}.svg"

  # CONFIGURACIÓN DE GROSOR
  # Por defecto: Close elimina ruido sin cambiar el grosor significativamente
  MORPH_OP="Close Disk:1"
  
  if [[ "$name" == *"_thick"* ]]; then
    echo "Engrosando líneas para: $filename"
    # Erode expande el negro. Prueba Disk:2 o Disk:3 si lo quieres aún más grueso.
    MORPH_OP="Erode Disk:2"
  fi

  echo "Procesando $filename -> $target"

  # Pipeline con corrección de fondo blanco y engrosamiento
  $IMG_TOOL "$img" \
    -fuzz 18% \
    -fill white -draw "color 0,0 floodfill" \
    -colorspace Gray \
    -auto-level \
    -threshold 55% \
    -morphology $MORPH_OP \
    "${name}_bn.png"

  # Aseguramos que el BMP sea puro negro/blanco para potrace
  $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
  
  potrace "${name}.bmp" -s -o "$target"
  
  rm "${name}_bn.png" "${name}.bmp" "$img" 
done