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

  # --- MODO COLOR (Limpia transparencias) ---
  if [[ "$name" == *"_color"* && "$name" != *"_multicolor"* ]]; then
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
      
  # --- NUEVO MODO: MULTICOLOR (Separación Inteligente por Colores Reales) ---
  elif [[ "$name" == *"_multicolor"* ]]; then
    echo "  -> Modo Multi-Color: Separando capas por color detectado para $filename..."
    target_svg="output/design/${name}.svg"
    generated_svg="$target_svg"
    
    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"

    echo "    [Debug] Escaneando colores en la imagen..."
    # 1. Quitamos fondos transparentes y reducimos la imagen a un máximo de 6 colores puros
    $IMG_TOOL "$img" -fuzz 20% -fill white -draw "color 0,0 floodfill" -background white -alpha remove -fuzz 10% +dither -colors 6 "temp_flat.png"
    
    # 2. Extraemos los códigos HEX de los colores detectados (Ignorando el blanco)
    DETECTED_COLORS=$($IMG_TOOL "temp_flat.png" -format "%c" histogram:info: | grep -oE '#[0-9a-fA-F]{6}' | grep -ivE '#FFFFFF' | sort -u)
    
    echo "    [Debug] Colores detectados para separar: $(echo $DETECTED_COLORS | tr '\n' ' ')"

    if [ -z "$DETECTED_COLORS" ]; then
         echo "    [Alerta] No se detectaron colores válidos."
    else
        counter=1
        for color in $DETECTED_COLORS; do
            echo "    [Debug] Aislando y vectorizando el color: $color"
            
            # EL SECRETO: Convertir SOLO el color actual a negro, y todo lo demás a blanco
            $IMG_TOOL "temp_flat.png" -fuzz 15% -fill black -opaque "$color" -fuzz 15% -fill white +opaque black "temp_${counter}.bmp"
            
            # Potrace vectoriza ese color perfectamente, respetando los huecos
            potrace "temp_${counter}.bmp" -s -o "temp_${counter}.svg"
            
            # Aplanamos el código para Canva
            FLAT_SVG=$(tr '\n' ' ' < "temp_${counter}.svg")
            PATH_DATA=$(echo "$FLAT_SVG" | grep -o 'd="[^"]*"' | head -n 1)
            TRANSFORM_DATA=$(echo "$FLAT_SVG" | grep -o 'transform="[^"]*"' | head -n 1)

            if [ ! -z "$PATH_DATA" ]; then
                echo "  <path id=\"layer-${counter}\" class=\"icon-part\" fill=\"$color\" $TRANSFORM_DATA $PATH_DATA />" >> "$target_svg"
            else
                echo "    [Aviso] El color $color no generó trazado."
            fi
            
            rm -f "temp_${counter}.bmp" "temp_${counter}.svg"
            counter=$((counter + 1))
        done
    fi
    
    echo "</svg>" >> "$target_svg"
    rm -f "temp_flat.png"

    echo "    [Debug] Optimizando y fusionando transformaciones para Canva..."
    svgo "$target_svg" --multipass --output "$target_svg"
    
  # --- MODO CAPAS CLÁSICO (Desconectados, por si lo necesitas en el futuro) ---
  elif [[ "$name" == *"_layers"* ]]; then
    echo "  -> Modo Capas (Clásico): Separando por islas para $filename..."
    target_svg="output/design/${name}.svg"
    generated_svg="$target_svg"
    
    $IMG_TOOL "$img" -fuzz 20% -fill white -draw "color 0,0 floodfill" \
      -colorspace Gray -threshold 55% -morphology Close Disk:1 "temp_binary.bmp"

    CC_OUTPUT=$($IMG_TOOL "temp_binary.bmp" -define connected-components:verbose=true -define connected-components:area-threshold=5 -connected-components 4 null: | tr -d '\r')
    BLACK_IDS=$(echo "$CC_OUTPUT" | tail -n +2 | grep -iE "srgba\(0,0,0|srgb\(0,0,0|gray\(0|black|#000000" | awk '{print $1}' | sed 's/://')
    BLACK_IDS_CLEAN=$(echo $BLACK_IDS | xargs)

    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"

    if [ -n "$BLACK_IDS_CLEAN" ]; then
        COLORS=("#33CCFF" "#FF3366" "#33FF66" "#CC33FF" "#00FFFF")
        color_index=0
        counter=1

        for id in $BLACK_IDS; do
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
            FLAT_SVG=$(tr '\n' ' ' < "temp_${counter}.svg")
            PATH_DATA=$(echo "$FLAT_SVG" | grep -o 'd="[^"]*"' | head -n 1)
            TRANSFORM_DATA=$(echo "$FLAT_SVG" | grep -o 'transform="[^"]*"' | head -n 1)

            if [ -n "$PATH_DATA" ]; then
                echo "  <path id=\"layer-${counter}\" class=\"icon-part\" fill=\"$CURRENT_COLOR\" $TRANSFORM_DATA $PATH_DATA />" >> "$target_svg"
            fi
            
            rm -f "temp_${counter}.bmp" "temp_${counter}.svg"
            counter=$((counter + 1))
            color_index=$((color_index + 1))
        done
    fi
    echo "</svg>" >> "$target_svg"
    rm -f "temp_binary.bmp"
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
