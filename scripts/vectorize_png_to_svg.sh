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
  echo "Procesando con Detección de Color: $filename"

  # Obtener dimensiones
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  CENTER_X=$((WIDTH / 2))
  CENTER_Y=$((HEIGHT / 2))

  # --- MODO A: CONSERVAR COLOR (_color) ---
  if [[ "$name" == *"_color"* ]]; then
    target_png="output/design/${name}_transparent.png"
    
    # 1. DETECTAR COLOR DE FONDO (Esquina 0,0)
    BG_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info:)
    echo "Color de fondo detectado: $BG_COLOR"

    # 2. CREAR MÁSCARA BASADA EN ESE COLOR
    # Usamos un fuzz del 30% para atrapar sombras grises del fondo.
    # El resultado es un mapa donde la madera es BLANCA y el fondo NEGRO.
    $IMG_TOOL "$img" \
      -fuzz 30% \
      -transparent "$BG_COLOR" \
      -alpha extract \
      -threshold 0 \
      -negate \
      -morphology Close Disk:2 \
      "${name}_mask.png"

    # 3. PERFORAR EL HUECO CENTRAL EN LA MÁSCARA
    # Buscamos el color en el centro para perforarlo
    $IMG_TOOL "${name}_mask.png" \
      -fill black -draw "color $CENTER_X,$CENTER_Y floodfill" \
      "${name}_mask_final.png"

    # 4. APLICAR MÁSCARA A LA IMAGEN ORIGINAL
    # Usamos 'CopyOpacity' para que la máscara dicte qué es transparente.
    # '-trim' elimina los bordes vacíos automáticamente.
    $IMG_TOOL "$img" "${name}_mask_final.png" \
      -alpha off -compose CopyOpacity -composite \
      -trim +repage \
      "$target_png"
    
    echo "Recorte finalizado: $target_png"

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

  # Limpieza
  rm -f "${name}_mask.png" "${name}_mask_final.png" "${name}_bn.png" "${name}.bmp" "$img"
done