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
  echo "Error: ImageMagick no está instalado."
  exit 1
fi

mkdir -p output/design
mkdir -p output/web

shopt -s nullglob
FILES=(input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS})

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No hay imágenes nuevas para procesar en input/png/."
  exit 0
fi

# --- 2. PROCESAMIENTO ---
for img in "${FILES[@]}"; do
  filename=$(basename -- "$img")
  name="${filename%.*}"
  echo "----------------------------------------"
  echo "Procesando: $filename"
  
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  CENTER_X=$((WIDTH / 2))
  CENTER_Y=$((HEIGHT / 2))

  generated_svg=""

  # --- MODO COLOR ---
  if [[ "$name" == *"_color"* ]]; then
    echo "  -> Modo Color: Refinando transparencia..."
    target_png="output/design/${name}_transparent.png"
    BG_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info:)

    $IMG_TOOL "$img" \
      -alpha set \
      -fuzz 20% -fill none -draw "color 0,0 floodfill" \
      -fuzz 20% -fill none -draw "color $CENTER_X,$CENTER_Y floodfill" \
      -fuzz 10% -transparent white \
      -fuzz 10% -transparent "$BG_COLOR" \
      -channel A -morphology Erode Disk:1.2 +channel \
      -shave 1x1 -trim +repage \
      "$target_png"
    
  # --- MODO CAPAS: Lógica de Borrado + Estructura Plana Canva-Friendly ---
  elif [[ "$name" == *"_layers"* ]]; then
    echo "  -> Modo Capas: Separando elementos para $filename..."
    target_svg="output/design/${name}.svg"
    generated_svg="$target_svg"
    
    echo "    [Debug] Generando mapa binario..."
    $IMG_TOOL "$img" -fuzz 20% -fill white -draw "color 0,0 floodfill" \
      -colorspace Gray -threshold 55% -morphology Close Disk:1 "temp_binary.bmp"

    echo "    [Debug] Analizando topología..."
    CC_OUTPUT=$($IMG_TOOL "temp_binary.bmp" -define connected-components:verbose=true -define connected-components:area-threshold=5 -connected-components 4 null: | tr -d '\r')
    
    BLACK_IDS=$(echo "$CC_OUTPUT" | tail -n +2 | grep -iE "srgba\(0,0,0|srgb\(0,0,0|gray\(0|black|#000000" | awk '{print $1}' | sed 's/://')
    BLACK_IDS_CLEAN=$(echo $BLACK_IDS | xargs)

    echo "    [Debug] IDs de Piezas detectadas: $BLACK_IDS_CLEAN"

    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"

    if [ -z "$BLACK_IDS_CLEAN" ]; then
         echo "    [Alerta] No se detectaron piezas negras."
    else
        COLORS=("#33CCFF" "#FF3366" "#33FF66" "#CC33FF" "#00FFFF" "#FF9900" "#3366FF")
        color_index=0
        counter=1

        for id in $BLACK_IDS; do
            echo "    [Debug] Procesando capa ID: $id"
            CURRENT_COLOR="${COLORS[$color_index % ${#COLORS[@]}]}"
            
            REMOVE_LIST=""
            for other_id in $BLACK_IDS; do
                if [ "$other_id" != "$id" ]; then
                    REMOVE_LIST="$REMOVE_LIST $other_id"
                fi
            done
            REMOVE_CSV=$(echo $REMOVE_LIST | xargs | tr ' ' ',')

            if [ -z "$REMOVE_CSV" ]; then
                cp "temp_binary.bmp" "temp_${counter}.bmp"
            else
                $IMG_TOOL "temp_binary.bmp" \
                  -define connected-components:remove="${REMOVE_CSV}" \
                  -define connected-components:mean-color=true \
                  -connected-components 4 \
                  "temp_${counter}.bmp"
            fi
              
            potrace "temp_${counter}.bmp" -s -o "temp_${counter}.svg"
            
            # --- ESTRUCTURACIÓN CANVA-FRIENDLY ---
            # 1. Extraemos SOLO el trazado matemático de Potrace
            PATH_DATA=$(grep -o 'd="[^"]*"' "temp_${counter}.svg" | head -n 1)
            
            # 2. Extraemos la transformación de Potrace (para mantener la orientación)
            TRANSFORM_DATA=$(grep -o 'transform="[^"]*"' "temp_${counter}.svg" | head -n 1)

            # 3. Construimos un <path> limpio, sin grupos, con el color inyectado directamente
            if [ ! -z "$PATH_DATA" ]; then
                echo "  <path id=\"layer-${counter}\" class=\"icon-part\" fill=\"$CURRENT_COLOR\" $TRANSFORM_DATA $PATH_DATA />" >> "$target_svg"
            else
                echo "    [Aviso] La pieza $id no contenía tinta."
            fi
            # -------------------------------------
            
            rm -f "temp_${counter}.bmp" "temp_${counter}.svg"
            
            counter=$((counter + 1))
            color_index=$((color_index + 1))
        done
    fi
    
    echo "</svg>" >> "$target_svg"
    rm -f "temp_binary.bmp"

    # --- APLANADO FINAL CON SVGO (Exclusivo para _layers) ---
    # Esto fusiona las transformaciones y asegura la máxima compatibilidad
    svgo "$target_svg" --multipass --output "$target_svg"

  # --- MODO VECTOR (Standard) ---
  else
    echo "  -> Modo Estándar: Vectorización simple..."
    target_svg="output/design/${name}.svg"
    generated_svg="$target_svg"

    $IMG_TOOL "$img" -fuzz 20% -fill white -draw "color 0,0 floodfill" \
      -colorspace Gray -threshold 55% -morphology Close Disk:1 "${name}_bn.png"
    
    $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
    potrace "${name}.bmp" -s -o "$target_svg"
    
    if [[ "$name" == *"_hole"* ]]; then
      echo "  -> Generando marco PDF (_hole)..."
      rsvg-convert -f pdf -o "output/design/${name}_frame.pdf" "$target_svg"
    fi
    rm -f "${name}_bn.png" "${name}.bmp"
  fi

  # --- OPTIMIZACIÓN WEB ESPECÍFICA AUTOMÁTICA ---
  if [[ "$name" == *"_web"* && -n "$generated_svg" ]]; then
    echo "  -> Etiqueta _web detectada: Optimizando automáticamente..."
    svgo "$generated_svg" --multipass --output "output/web/${name}.min.svg"
  fi

  rm -f "$img"
done
