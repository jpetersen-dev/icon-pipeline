#!/bin/bash
set -e

# Detectar comando de ImageMagick (magick o convert)
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

# Ahora busca png, jpg, jpeg y eps (ignorando mayúsculas/minúsculas)
for img in input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS}; do
  [ -e "$img" ] || continue
  
  # Extraer nombre sin importar la extensión
  filename=$(basename -- "$img")
  name="${filename%.*}"
  target="output/design/${name}.svg"

  echo "Procesando $filename -> $target"

  # Pipeline con autodestrucción e iteración
  $IMG_TOOL "$img" \
    -alpha set -fuzz 18% -fill none -draw "$ALPHA_KEY 0,0 floodfill" \
    -colorspace Gray -auto-level -threshold 55% \
    -morphology Close Disk:1 "${name}_bn.png"

  $IMG_TOOL "${name}_bn.png" "${name}.bmp"
  potrace "${name}.bmp" -s -o "$target"
  
  # Limpieza: Borra temporales y el archivo ORIGINAL (sea jpg, png o eps)
  rm "${name}_bn.png" "${name}.bmp" "$img" 
done