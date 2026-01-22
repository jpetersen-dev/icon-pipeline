#!/bin/bash
set -e

# --- 1. DETECCIÓN DE HERRAMIENTAS ---
if command -v magick >/dev/null 2>&1; then
  IMG_TOOL="magick"
  ALPHA_KEY="alpha"
  IDENTIFY_TOOL="magick identify"
elif command -v convert >/dev/null 2>&1; then
  IMG_TOOL="convert"
  ALPHA_KEY="matte"
  IDENTIFY_TOOL="identify"
else
  echo "Error: ImageMagick no está instalado." >&2
  exit 1
fi

# Asegurar que existe la carpeta de salida
mkdir -p output/design

# --- 2. PROCESAMIENTO POR LOTES ---
# Busca png, jpg, jpeg y eps (sin importar mayúsculas)
for img in input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS}; do
  [ -e "$img" ] || continue
  
  filename=$(basename -- "$img")
  name="${filename%.*}"
  target="output/design/${name}.svg"

  echo "------------------------------------------------"
  echo "Analizando: $filename"

  # --- LÓGICA DE GROSOR (_thick) ---
  MORPH_OP="Close Disk:1" # Limpieza estándar
  if [[ "$name" == *"_thick"* ]]; then
    echo "[MODO] Engrosamiento detectado (Erode)."
    MORPH_OP="Erode Disk:2"
  fi

  # --- LÓGICA DE AGUJERO/MARCO (_hole) ---
  # Transparencia inicial en la esquina superior izquierda (0,0)
  DRAW_COMMANDS="-draw \"$ALPHA_KEY 0,0 floodfill\""
  
  if [[ "$name" == *"_hole"* ]]; then
    echo "[MODO] Creación de agujero central para Canva."
    # Obtener dimensiones y calcular el centro exacto
    DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
    WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
    HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
    CENTER_X=$((WIDTH / 2))
    CENTER_Y=$((HEIGHT / 2))
    
    # Añadir segundo clic de transparencia en el centro
    DRAW_COMMANDS="$DRAW_COMMANDS -fill white -draw \"$ALPHA_KEY $CENTER_X,$CENTER_Y floodfill\""
  fi

  # --- 3. PIPELINE DE IMAGEMAGICK ---
  # Convertimos a blanco y negro, aplicamos morfología y preparamos para potrace
  $IMG_TOOL "$img" \
    -fuzz 18% \
    -fill white $DRAW_COMMANDS \
    -colorspace Gray \
    -auto-level \
    -threshold 55% \
    -morphology $MORPH_OP \
    "${name}_bn.png"

  # Crear BMP temporal (limpio de transparencia para potrace)
  $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
  
  # --- 4. VECTORIZACIÓN ---
  # Generar el SVG (Potrace crea el trazado vectorial)
  potrace "${name}.bmp" -s -o "$target"

  # --- 5. GENERACIÓN DE MARCO NATIVO (PDF) ---
  if [[ "$name" == *"_hole"* ]]; then
    echo "Exportando PDF para Canva..."
    # rsvg-convert transforma el vector en un PDF que Canva reconoce como marco
    rsvg-convert -f pdf -o "output/design/${name}_frame.pdf" "$target"
  fi
  
  # --- 6. LIMPIEZA FINAL ---
  # Borra los archivos temporales y el ORIGINAL para ahorrar espacio
  rm "${name}_bn.png" "${name}.bmp" "$img"
  echo "Completado: $target"
done