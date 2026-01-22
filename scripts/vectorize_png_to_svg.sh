#!/bin/bash
set -e

# --- 1. DETECCIÓN DE HERRAMIENTAS ---
# Detectamos si usamos magick (IM7) o convert (IM6) y ajustamos los comandos
if command -v magick >/dev/null 2>&1; then
  IMG_TOOL="magick"
  IDENTIFY_TOOL="magick identify"
  # Comandos para IM7
  ALPHA_SET="-alpha set"
  CHANNEL_SELECT="-channel A"
  CHANNEL_RESET="+channel"
elif command -v convert >/dev/null 2>&1; then
  IMG_TOOL="convert"
  IDENTIFY_TOOL="identify"
  # Comandos para IM6 (compatibilidad con GitHub Actions)
  ALPHA_SET="-matte -channel A"
  CHANNEL_SELECT="-channel A"
  CHANNEL_RESET="+channel"
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

  # Obtener dimensiones para encontrar el centro
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  CENTER_X=$((WIDTH / 2))
  CENTER_Y=$((HEIGHT / 2))

  # --- MODO A: MANTENER COLOR Y TEXTURA (_color) ---
  if [[ "$name" == *"_color"* ]]; then
    echo "[MODO] Conservando texturas y realizando limpieza avanzada de bordes..."
    target_png="output/design/${name}_transparent.png"
    
    # NOTA TÉCNICA:
    # 1. Creamos la transparencia inicial con floodfill (con un fuzz generoso del 20%).
    # 2. Usamos '-morphology Erode' sobre el canal Alpha. Esto "raspa" la parte opaca
    #    de la imagen hacia adentro, eliminando los halos grises y bordes blancos.
    #    Disk:2.5 es la intensidad del raspado. Auméntalo si aún quedan bordes.
    # 3. Usamos '-transparent white' al final con un fuzz bajo para eliminar 
    #    pequeñas áreas blancas desconectadas dentro del diseño de madera.

    $IMG_TOOL "$img" \
      $ALPHA_SET \
      -fuzz 20% \
      -fill none -draw "color 0,0 floodfill" \
      -fill none -draw "color $CENTER_X,$CENTER_Y floodfill" \
      $CHANNEL_SELECT -morphology Erode Disk:2.5 $CHANNEL_RESET \
      -fuzz 10% -transparent white \
      "$target_png"
    
    echo "PNG con transparencia limpia creado: $target_png"

  # --- MODO B: VECTORIZACIÓN B&W (Iconos y Marcos vectoriales) ---
  else
    target_svg="output/design/${name}.svg"
    
    # Configuración estándar para B&W
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

  # Limpieza
  rm -f "${name}_bn.png" "${name}.bmp" "$img"
done