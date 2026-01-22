#!/bin/bash
set -e

# --- 1. CONFIGURACIÓN DE HERRAMIENTAS ---
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
  echo "Procesando con Máscara Quirúrgica: $filename"

  # Obtener dimensiones
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  CENTER_X=$((WIDTH / 2))
  CENTER_Y=$((HEIGHT / 2))

  # --- MODO A: CONSERVAR COLOR (_color) ---
  if [[ "$name" == *"_color"* ]]; then
    target_png="output/design/${name}_transparent.png"
    
    # PASO 1: Crear una máscara de contraste extremo
    # Esto genera un mapa B&W donde la madera es NEGRA y el fondo es BLANCO.
    # Al usar '-threshold 92%', protegemos las luces de la madera.
    $IMG_TOOL "$img" \
      -colorspace Gray \
      -threshold 92% \
      -negate \
      -morphology Close Disk:2 \
      "${name}_mask.png"

    # PASO 2: Perforar la máscara en el centro y esquinas
    $IMG_TOOL "${name}_mask.png" \
      -fill black -draw "color 0,0 floodfill" \
      -fill black -draw "color $CENTER_X,$CENTER_Y floodfill" \
      "${name}_mask_final.png"

    # PASO 3: Aplicar la máscara como Canal Alfa a la imagen original
    # Esto mantiene CADA PÍXEL de color original pero oculta el fondo.
    $IMG_TOOL "$img" "${name}_mask_final.png" \
      -alpha off -compose CopyOpacity -composite \
      -trim +repage \
      "$target_png"
    
    echo "PNG Limpio (Preservando Luces): $target_png"

  # --- MODO B: VECTORIZACIÓN ESTÁNDAR ---
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

  # Limpieza de temporales
  rm -f "${name}_mask.png" "${name}_mask_final.png" "${name}_bn.png" "${name}.bmp" "$img"
done