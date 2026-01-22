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
  echo "Error: ImageMagick no está instalado." >&2
  exit 1
fi

mkdir -p output/design

# --- 2. PROCESAMIENTO ---
for img in input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS}; do
  [ -e "$img" ] || continue
  
  filename=$(basename -- "$img")
  name="${filename%.*}"
  target="output/design/${name}.svg"

  echo "------------------------------------------------"
  echo "Procesando: $filename"

  # Creamos un Array para los comandos de ImageMagick
  # Esto evita errores de espacios y comillas
  IM_ARGS=(-fuzz 18% -fill none)

  # A) Siempre quitamos el fondo exterior (esquina 0,0)
  IM_ARGS+=(-draw "color 0,0 floodfill")

  # B) Lógica de Agujero Central (_hole)
  if [[ "$name" == *"_hole"* ]]; then
    echo "[MODO] Agujero central detectado."
    DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
    WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
    HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
    CENTER_X=$((WIDTH / 2))
    CENTER_Y=$((HEIGHT / 2))
    
    # Añadimos el segundo clic en el centro
    IM_ARGS+=(-draw "color $CENTER_X,$CENTER_Y floodfill")
  fi

  # C) Lógica de Grosor (_thick)
  MORPH_OP="Close Disk:1"
  if [[ "$name" == *"_thick"* ]]; then
    echo "[MODO] Engrosamiento detectado."
    MORPH_OP="Erode Disk:2"
  fi

  # --- 3. EJECUCIÓN ---
  # Aplicamos el procesamiento de imagen
  # Usamos "${IM_ARGS[@]}" para que Bash pase los argumentos exactamente como los definimos
  $IMG_TOOL "$img" \
    "${IM_ARGS[@]}" \
    -colorspace Gray \
    -auto-level \
    -threshold 55% \
    -morphology $MORPH_OP \
    "${name}_bn.png"

  # Convertir a BMP para Potrace (asegurando fondo blanco)
  $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
  
  # Generar SVG
  potrace "${name}.bmp" -s -o "$target"

  # Generar PDF para Canva si es un marco
  if [[ "$name" == *"_hole"* ]]; then
    rsvg-convert -f pdf -o "output/design/${name}_frame.pdf" "$target"
  fi
  
  # Limpieza
  rm "${name}_bn.png" "${name}.bmp" "$img"
done