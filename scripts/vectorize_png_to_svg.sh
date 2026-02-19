#!/bin/bash
set -e

if command -v magick >/dev/null 2>&1; then IMG_TOOL="magick"; IDENTIFY_TOOL="magick identify"
elif command -v convert >/dev/null 2>&1; then IMG_TOOL="convert"; IDENTIFY_TOOL="identify"
else echo "Error: ImageMagick no está instalado."; exit 1; fi

mkdir -p output/design; mkdir -p output/web
shopt -s nullglob
FILES=(input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS})

if [ ${#FILES[@]} -eq 0 ]; then exit 0; fi

for img in "${FILES[@]}"; do
  filename=$(basename -- "$img")
  name="${filename%.*}"
  echo "----------------------------------------"
  echo "Procesando: $filename"
  
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  target_svg="output/design/${name}.svg"

  if [[ "$name" == *"_layers"* || "$name" == *"_multicolor"* ]]; then
    echo "  -> Modo Híbrido: Separación geométrica + Agrupación por color real..."
    
    # Reducimos los colores de la original a máximo 6 para facilitar el muestreo
    $IMG_TOOL "$img" -background white -alpha remove +dither -colors 6 "temp_reduced_colors.png"

    echo "    [Debug] Creando mapa de siluetas..."
    $IMG_TOOL "$img" -background white -alpha remove -fuzz 20% -fill white -draw "color 0,0 floodfill" -colorspace Gray -threshold 55% -morphology Close Disk:1 "temp_binary.bmp"

    echo "    [Debug] Analizando topología..."
    CC_OUTPUT=$($IMG_TOOL "temp_binary.bmp" -define connected-components:verbose=true -define connected-components:area-threshold=10 -connected-components 4 null: | tr -d '\r')
    
    BG_ID=$(echo "$CC_OUTPUT" | tail -n +2 | head -n 1 | awk '{print $1}' | sed 's/://')
    BLACK_IDS=$(echo "$CC_OUTPUT" | tail -n +2 | awk '{if ($1 != "'"$BG_ID"':" && $1 != "") print $1}' | sed 's/://')

    if [ -z "$BLACK_IDS" ]; then
         echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\"></svg>" > "$target_svg"
    else
        echo "    [Debug] Muestreando color original de cada pieza..."
        declare -A COLOR_GROUPS
        
        for id in $BLACK_IDS; do
            # MÉTODO SEGURO DE MUESTREO:
            # 1. Aislamos la pieza
            $IMG_TOOL "temp_binary.bmp" -define connected-components:keep="$id" -connected-components 4 "temp_mask_$id.bmp"
            
            # 2. Copiamos el color original solo donde la máscara es negra, el resto lo hacemos transparente
            $IMG_TOOL "temp_reduced_colors.png" "temp_mask_$id.bmp" -compose CopyOpacity -composite -transparent white "temp_color_$id.png"

            # 3. Extraemos el color más usado ignorando transparencias
            DOMINANT_COLOR=$($IMG_TOOL "temp_color_$id.png" -format "%c" histogram:info: | grep -ivE 'none|#00000000|#FFFFFF|#FEFEFE|#FDFDFD|#F0F0F0' | sort -nr | head -n 1 | grep -oE '#[0-9a-fA-F]{6}' || true)
            
            if [ -z "$DOMINANT_COLOR" ]; then DOMINANT_COLOR="#000000"; fi
            
            echo "      - Isla $id -> Color detectado: $DOMINANT_COLOR"
            COLOR_GROUPS["$DOMINANT_COLOR"]="${COLOR_GROUPS["$DOMINANT_COLOR"]} $id"
            
            rm -f "temp_mask_$id.bmp" "temp_color_$id.png"
        done

        echo "    [Debug] Vectorizando grupos consolidados de color..."
        echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"
        counter=1
        
        for hex_color in "${!COLOR_GROUPS[@]}"; do
            ids_to_keep="${COLOR_GROUPS[$hex_color]}"
            ids_csv=$(echo $ids_to_keep | xargs | tr ' ' ',')
            
            # Aislar el grupo completo usando el CSV de IDs a mantener
            $IMG_TOOL "temp_binary.bmp" -define connected-components:keep="$ids_csv" -connected-components 4 "temp_group_${counter}.bmp"
            
            # Vectorizar
            potrace "temp_group_${counter}.bmp" -s -o "temp_group_${counter}.svg"
            
            # SOLUCIÓN ANTI-BROKEN-PIPE: Extraemos el bloque 'g' completo con sed
            G_BLOCK=$(sed -n '/<g transform=/,/<\/g>/p' "temp_group_${counter}.svg" | sed 's/fill="#000000"/fill="'"$hex_color"'"/g' | sed 's/fill="black"/fill="'"$hex_color"'"/g')
            
            if [ ! -z "$G_BLOCK" ]; then
                echo "  <g id=\"layer-color-${counter}\" class=\"icon-part\">" >> "$target_svg"
                echo "$G_BLOCK" >> "$target_svg"
                echo "  </g>" >> "$target_svg"
            fi
            
            rm -f "temp_group_${counter}.bmp" "temp_group_${counter}.svg"
            counter=$((counter + 1))
        done
        echo "</svg>" >> "$target_svg"
    fi
    
    rm -f "temp_binary.bmp" "temp_reduced_colors.png"
    echo "    [Debug] Optimizando SVG final para Canva..."
    # SVGO se encargará de "aplanar" esos bloques <g> que insertamos arriba
    svgo "$target_svg" --multipass --output "$target_svg"

  # --- MODO ESTÁNDAR ---
  else
    target_svg="output/design/${name}.svg"
    $IMG_TOOL "$img" -fuzz 20% -fill white -draw "color 0,0 floodfill" -colorspace Gray -threshold 55% -morphology Close Disk:1 "${name}_bn.png"
    $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
    potrace "${name}.bmp" -s -o "$target_svg"
    rm -f "${name}_bn.png" "${name}.bmp"
  fi

  if [[ "$name" == *"_web"* && -f "output/design/${name}.svg" ]]; then
    svgo "output/design/${name}.svg" --multipass --output "output/web/${name}.min.svg"
  fi

  rm -f "$img"
done