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
  echo "Error: ImageMagick no instalado." >&2
  exit 1
fi

mkdir -p output/design

# --- 2. PROCESAMIENTO ---
for img in input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS}; do
  [ -e "$img" ] || continue
  filename=$(basename -- "$img")
  name="${filename%.*}"
  
  echo "------------------------------------------------"
  echo "Procesando: $filename"

  # Obtener dimensiones para el centro
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  CENTER_X=$((WIDTH / 2))
  CENTER_Y=$((HEIGHT / 2))

  # --- MODO A: MANTENER COLOR Y TEXTURA (_color) ---
  if [[ "$name" == *"_color"* ]]; then
    echo "[MODO] Conservando texturas y perforando transparencia..."
    target_png="output/design/${name}_transparent.png"
    
    # IMPORTANTE: Usamos 'color X,Y floodfill' con '-fill none' para IM6/IM7
    $IMG_TOOL "$img" \
      -alpha set \
      -fuzz 15% \
      -fill none -draw "color 0,0 floodfill" \
      -fill none -draw "color $CENTER_X,$CENTER_Y floodfill" \
      "$target_png"
    
    echo "PNG con transparencia creado: $target_png"

  # --- MODO B: VECTORIZACIÓN B&W (Iconos y Marcos de un solo color) ---
  else
    target_svg="output/design/${name}.svg"
    
    # Configuración de dibujo para B&W
    IM_ARGS=(-fuzz 18% -fill white -draw "color 0,0 floodfill")
    [[ "$name" == *"_hole"* ]] && IM_ARGS+=(-draw "color $CENTER_X,$CENTER_Y floodfill")

    MORPH_OP="Close Disk:1"
    [[ "$name" == *"_thick"* ]] && MORPH_OP="Erode Disk:2"

    $IMG_TOOL "$img" \
      "${IM_ARGS[@]}" \
      -colorspace Gray -auto-level -threshold 55% \
      -morphology $MORPH_OP \
      "${name}_bn.png"

    $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
    potrace "${name}.bmp" -s -o "$target_svg"
    
    if [[ "$name" == *"_hole"* ]]; then
      rsvg-convert -f pdf -o "output/design/${name}_frame.pdf" "$target_svg"
    fi
  fi

  # Limpieza de archivos originales y temporales
  rm -f "${name}_bn.png" "${name}.bmp" "$img"
done