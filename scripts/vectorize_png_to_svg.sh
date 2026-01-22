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
  
  # Obtener dimensiones para el centro exacto
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  CENTER_X=$((WIDTH / 2))
  CENTER_Y=$((HEIGHT / 2))

  # --- MODO COLOR: MANTENER MADERA Y QUITAR FONDO/HUECOS ---
  if [[ "$name" == *"_color"* ]]; then
    echo "Procesando madera con transparencia directa: $filename"
    target_png="output/design/${name}_transparent.png"
    
    # 1. Detectar el color exacto del fondo en la esquina
    BG_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info:)

    # 2. PROCESO DE TRANSPARENCIA:
    # -fuzz 25%: Tolerancia para atrapar sombras grises claras.
    # -draw 'color...floodfill': Agujerea el fondo y el centro.
    # -shave 1x1: Elimina el posible borde de 1px que deja la IA.
    # -trim: Ajusta el archivo final al tamaño real del marco.
    $IMG_TOOL "$img" \
      -alpha set \
      -fuzz 25% \
      -fill none -draw "color 0,0 floodfill" \
      -fill none -draw "color $CENTER_X,$CENTER_Y floodfill" \
      -shave 1x1 -trim +repage \
      "$target_png"
    
    echo "PNG de madera listo: $target_png"

  # --- MODO VECTOR: PARA ICONOS Y MARCOS DE UN SOLO COLOR ---
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