#!/bin/bash
set -e

# --- 1. DETECCIÓN DE HERRAMIENTAS ---
if command -v magick >/dev/null 2>&1; then
  IMG_TOOL="magick"
  IDENTIFY_TOOL="magick identify"
  ALPHA_SET="-alpha set"
  CHANNEL_SELECT="-channel A"
  CHANNEL_RESET="+channel"
  # Para IM7, el color transparente se define así
  TRANSPARENT_COLOR="none"
elif command -v convert >/dev/null 2>&1; then
  IMG_TOOL="convert"
  IDENTIFY_TOOL="identify"
  # Para IM6 (GitHub), usamos matte para el canal alfa
  ALPHA_SET="-matte -channel A"
  CHANNEL_SELECT="-channel A"
  CHANNEL_RESET="+channel"
  # Para IM6, el color transparente para floodfill es 'none'
  TRANSPARENT_COLOR="none"
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

  # Obtener dimensiones
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  CENTER_X=$((WIDTH / 2))
  CENTER_Y=$((HEIGHT / 2))

  # --- MODO A: MANTENER COLOR Y TEXTURA (_color) ---
  if [[ "$name" == *"_color"* ]]; then
    echo "[MODO] Conservando texturas con limpieza AGRESIVA..."
    target_png="output/design/${name}_transparent.png"
    
    # NOTA TÉCNICA DE LA NUEVA VERSIÓN:
    # 1. Fuzz inicial alto (25%): Para atrapar más sombras grises en el floodfill.
    # 2. Erode fuerte (Disk:3.5): Raspamos más los bordes para eliminar halos.
    # 3. PASO FINAL CRÍTICO: '-fuzz 15% -transparent white'. 
    #    Esto busca cualquier píxel blanco/gris claro que haya quedado AISLADO
    #    dentro de los huecos del tallado y lo elimina.

    $IMG_TOOL "$img" \
      $ALPHA_SET \
      -fuzz 25% \
      -fill "$TRANSPARENT_COLOR" -draw "color 0,0 floodfill" \
      -fill "$TRANSPARENT_COLOR" -draw "color $CENTER_X,$CENTER_Y floodfill" \
      $CHANNEL_SELECT -morphology Erode Disk:3.5 $CHANNEL_RESET \
      -fuzz 15% -transparent white \
      "$target_png"
    
    echo "PNG con transparencia limpia creado: $target_png"

  # --- MODO B: VECTORIZACIÓN B&W ---
  else
    target_svg="output/design/${name}.svg"
    
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

  rm -f "${name}_bn.png" "${name}.bmp" "$img"
done