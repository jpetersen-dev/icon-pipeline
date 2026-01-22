#!/bin/bash
set -e

if command -v magick >/dev/null 2>&1; then
  IMG_TOOL="magick"
  IDENTIFY_TOOL="magick identify"
elif command -v convert >/dev/null 2>&1; then
  IMG_TOOL="convert"
  IDENTIFY_TOOL="identify"
else
  echo "Error: ImageMagick no instalado." >&2
  exit 1
fi

mkdir -p output/design

for img in input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS}; do
  [ -e "$img" ] || continue
  filename=$(basename -- "$img")
  name="${filename%.*}"
  
  echo "------------------------------------------------"
  echo "Procesando Imagen Real: $filename"

  # 1. Obtener Dimensiones
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  CENTER_X=$((WIDTH / 2))
  CENTER_Y=$((HEIGHT / 2))

  # 2. CASO: MANTENER COLOR (_color)
  if [[ "$name" == *"_color"* ]]; then
    echo "[MODO] Manteniendo colores y texturas originales..."
    target_png="output/design/${name}_transparent.png"
    
    # Crea transparencia en el fondo (0,0) y en el centro (hueco)
    $IMG_TOOL "$img" \
      -fuzz 15% \
      -fill none -draw "alpha $CENTER_X,$CENTER_Y floodfill" \
      -fill none -draw "alpha 0,0 floodfill" \
      "$target_png"
    
    echo "PNG Transparente creado: $target_png"
  
  # 3. CASO: VECTORIZACIÓN ESTÁNDAR (B&W)
  else
    target_svg="output/design/${name}.svg"
    IM_ARGS=(-fuzz 18% -fill white -draw "color 0,0 floodfill")
    
    if [[ "$name" == *"_hole"* ]]; then
      IM_ARGS+=(-draw "color $CENTER_X,$CENTER_Y floodfill")
    fi

    MORPH_OP="Close Disk:1"
    [[ "$name" == *"_thick"* ]] && MORPH_OP="Erode Disk:2"

    $IMG_TOOL "$img" "${IM_ARGS[@]}" -colorspace Gray -auto-level -threshold 55% -morphology $MORPH_OP "${name}_bn.png"
    $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
    potrace "${name}.bmp" -s -o "$target_svg"
    
    if [[ "$name" == *"_hole"* ]]; then
      rsvg-convert -f pdf -o "output/design/${name}_frame.pdf" "$target_svg"
    fi
  fi

  # Limpieza
  rm -f "${name}_bn.png" "${name}.bmp" "$img"
done