#!/bin/bash
set -e

# --- 1. DETECCIÓN DE HERRAMIENTAS ---
if command -v magick >/dev/null 2>&1; then
  IMG_TOOL="magick"
  IDENTIFY_TOOL="magick identify"
elif command -v convert >/dev/null 2>&1; then
  IMG_TOOL="convert"
  IDENTIFY_TOOL="identify"
else
  exit 1
fi

mkdir -p output/design

# --- 2. PROCESAMIENTO ---
for img in input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS}; do
  [ -e "$img" ] || continue
  filename=$(basename -- "$img")
  name="${filename%.*}"
  
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  CENTER_X=$((WIDTH / 2))
  CENTER_Y=$((HEIGHT / 2))

  # --- MODO COLOR: LIMPIEZA DE "ISLAS" BLANCAS ---
  if [[ "$name" == *"_color"* ]]; then
    echo "Refinando transparencia y eliminando islas: $filename"
    target_png="output/design/${name}_transparent.png"
    
    # Detectar el color exacto del fondo
    BG_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info:)

    # EXPLICACIÓN DEL REFINAMIENTO:
    # 1. '-fuzz 20% floodfill': Perfora las áreas grandes conectadas al fondo y centro.
    # 2. '-fuzz 10% -transparent white': Esta es la clave. Busca cualquier pixel "casi blanco" 
    #    que haya quedado aislado (islas) y lo vuelve transparente.
    # 3. '-channel A -morphology Erode Disk:1.2': Suaviza los bordes internos de los huecos 
    #    para que no queden rastros de "caspa" blanca.
    $IMG_TOOL "$img" \
      -alpha set \
      -fuzz 20% -fill none -draw "color 0,0 floodfill" \
      -fuzz 20% -fill none -draw "color $CENTER_X,$CENTER_Y floodfill" \
      -fuzz 10% -transparent white \
      -fuzz 10% -transparent "$BG_COLOR" \
      -channel A -morphology Erode Disk:1.2 +channel \
      -shave 1x1 -trim +repage \
      "$target_png"
    
    echo "Imagen refinada lista: $target_png"

  # --- MODO VECTOR (Standard) ---
  else
    target_svg="output/design/${name}.svg"
    $IMG_TOOL "$img" -fuzz 20% -fill white -draw "color 0,0 floodfill" \
      -colorspace Gray -threshold 55% -morphology Close Disk:1 "${name}_bn.png"
    
    $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
    potrace "${name}.bmp" -s -o "$target_svg"
    
    if [[ "$name" == *"_hole"* ]]; then
      rsvg-convert -f pdf -o "output/design/${name}_frame.pdf" "$target_svg"
    fi
  fi

  rm -f "${name}_bn.png" "${name}.bmp" "$img"
done