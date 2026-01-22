#!/bin/bash
set -e

# --- 1. DETECCIÓN DE HERRAMIENTAS ---
if command -v magick >/dev/null 2>&1; then
  IMG_TOOL="magick"
  IDENTIFY_TOOL="magick identify"
  ALPHA_SET="-alpha set"
  CHANNEL_SELECT="-channel A"
  CHANNEL_RESET="+channel"
elif command -v convert >/dev/null 2>&1; then
  IMG_TOOL="convert"
  IDENTIFY_TOOL="identify"
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
  echo "Procesando con Limpieza Nuclear: $filename"

  # Obtener dimensiones
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  CENTER_X=$((WIDTH / 2))
  CENTER_Y=$((HEIGHT / 2))

  # --- MODO A: MANTENER COLOR Y TEXTURA (_color) ---
  if [[ "$name" == *"_color"* ]]; then
    target_png="output/design/${name}_transparent.png"
    
    # EXPLICACIÓN DE LA MEJORA:
    # 1. '-level 0%,85%': Todo lo que tenga más de 85% de brillo se vuelve BLANCO PURO. 
    #    Esto elimina las sombras grises suaves de la IA.
    # 2. Fuzz al 35%: Muy agresivo para ignorar variaciones en los bordes.
    # 3. Morphology Erode Disk:4: Un raspado profundo para asegurar que no queden hilos blancos.

    $IMG_TOOL "$img" \
      -level 0%,85% \
      $ALPHA_SET \
      -fuzz 35% \
      -fill none -draw "color 0,0 floodfill" \
      -fill none -draw "color $CENTER_X,$CENTER_Y floodfill" \
      $CHANNEL_SELECT -morphology Erode Disk:4 $CHANNEL_RESET \
      -fuzz 20% -transparent white \
      "$target_png"
    
    echo "Resultado ultra-limpio creado: $target_png"

  # --- MODO B: VECTORIZACIÓN B&W ---
  else
    target_svg="output/design/${name}.svg"
    IM_ARGS=(-fuzz 25% -fill white -draw "color 0,0 floodfill")
    [[ "$name" == *"_hole"* ]] && IM_ARGS+=(-draw "color $CENTER_X,$CENTER_Y floodfill")

    MORPH_OP="Close Disk:1"
    [[ "$name" == *"_thick"* ]] && MORPH_OP="Erode Disk:2.5"

    $IMG_TOOL "$img" \
      -level 0%,80% \
      "${IM_ARGS[@]}" \
      -colorspace Gray -auto-level -threshold 50% \
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