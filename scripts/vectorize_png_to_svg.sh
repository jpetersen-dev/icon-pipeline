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
  # Por defecto usamos Close para limpiar píxeles fantasmas
  MORPH_OP="Close Disk:1"
  
  # Si el nombre contiene "_thick", aplicamos Dilatación para engrosar las líneas
  if [[ "$name" == *"_thick"* ]]; then
    echo "Aplicando engrosamiento de líneas para: $filename"
    # 'Dilate' expande las áreas negras. Prueba con Disk:1.5 o Disk:2 para más grosor.
    MORPH_OP="Dilate Disk:3"
  fi

  echo "Procesando $filename -> $target"

  $IMG_TOOL "$img" \
    -alpha set -fuzz 18% -fill none -draw "$ALPHA_KEY 0,0 floodfill" \
    -colorspace Gray -auto-level -threshold 55% \
    -morphology $MORPH_OP "${name}_bn.png"

  $IMG_TOOL "${name}_bn.png" "${name}.bmp"
  potrace "${name}.bmp" -s -o "$target"
  
  rm "${name}_bn.png" "${name}.bmp" "$img" 
done