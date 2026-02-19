#!/bin/bash
set -e

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

for img in "${FILES[@]}"; do
  filename=$(basename -- "$img")
  name="${filename%.*}"
  echo "----------------------------------------"
  echo "Procesando: $filename"
  
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)

  generated_svg=""

  if [[ "$name" == *"_multicolor"* ]]; then
    echo "  -> Modo Multi-Color: Separación Avanzada (Islas + Color Predominante)..."
    target_svg="output/design/${name}.svg"
    generated_svg="$target_svg"
    
    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"

    echo "    [Debug] 1. Creando mapa binario de alto contraste..."
    # Aplanamos sobre blanco y forzamos un binarizado fuerte para eliminar el antialiasing
    $IMG_TOOL "$img" -background white -alpha remove -colorspace Gray -fuzz 40% -threshold 60% -morphology Close Disk:1 "temp_binary_map.bmp"

    echo "    [Debug] 2. Identificando 'islas' (trazos separados)..."
    CC_OUTPUT=$($IMG_TOOL "temp_binary_map.bmp" -define connected-components:verbose=true -define connected-components:area-threshold=10 -connected-components 4 null: | tr -d '\r')
    
    # Identificamos el fondo (suele ser el objeto blanco más grande)
    BG_ID=$(echo "$CC_OUTPUT" | tail -n +2 | grep -iE "white|#FFFFFF|255|,255,255\)|gray\(255\)" | head -n 1 | awk '{print $1}' | sed 's/://')
    
    # Obtenemos las islas negras (trazos)
    BLACK_IDS=$(echo "$CC_OUTPUT" | tail -n +2 | awk '{if ($1 != "'"$BG_ID"':" && $1 != "") print $1}' | sed 's/://')
    
    if [ -z "$BLACK_IDS" ]; then
         echo "    [Alerta] No se detectaron trazos."
    else
        echo "    [Debug] 3. Determinando el color original de cada isla..."
        
        # Array asociativo para agrupar IDs por su color predominante
        declare -A COLOR_GROUPS
        
        for id in $BLACK_IDS; do
            # Aislar esta isla en blanco y negro
            $IMG_TOOL "temp_binary_map.bmp" -define connected-components:keep="$id" -connected-components 4 "temp_mask_$id.bmp"
            
            # Usar la isla como máscara sobre la imagen original a color para obtener solo el color de ese trazo
            # Luego, encontramos el color más frecuente en esa zona
            DOMINANT_COLOR=$($IMG_TOOL "$img" "temp_mask_$id.bmp" -alpha off -compose CopyOpacity -composite -scale 50x50! -format "%c" histogram:info: | grep -v "none" | sort -nr | head -n 1 | grep -oE '#[0-9a-fA-F]{6}')
            
            # Si no encuentra un color claro, asume negro por defecto
            if [ -z "$DOMINANT_COLOR" ]; then
                DOMINANT_COLOR="#000000"
            fi
            
            echo "      - Isla $id -> Color: $DOMINANT_COLOR"
            
            # Agrupar IDs por color
            COLOR_GROUPS["$DOMINANT_COLOR"]="${COLOR_GROUPS["$DOMINANT_COLOR"]} $id"
            
            rm -f "temp_mask_$id.bmp"
        done

        echo "    [Debug] 4. Vectorizando grupos de colores..."
        counter=1
        for color in "${!COLOR_GROUPS[@]}"; do
            ids_in_group="${COLOR_GROUPS[$color]}"
            # Limpiar espacios extra
            ids_in_group=$(echo $ids_in_group | xargs | tr ' ' ',')
            
            echo "      - Procesando Grupo Color: $color (Islas: $ids_in_group)"
            
            # Aislar todas las islas de este color en un solo mapa binario
            $IMG_TOOL "temp_binary_map.bmp" \
              -define connected-components:keep="$ids_in_group" \
              -connected-components 4 \
              "temp_group_${counter}.bmp"
              
            # Vectorizar el grupo completo
            potrace "temp_group_${counter}.bmp" -s -o "temp_group_${counter}.svg"
            
            # Extraer y aplanar para Canva
            FLAT_SVG=$(tr '\n' ' ' < "temp_group_${counter}.svg")
            PATH_DATA=$(echo "$FLAT_SVG" | grep -o 'd="[^"]*"' | head -n 1)
            TRANSFORM_DATA=$(echo "$FLAT_SVG" | grep -o 'transform="[^"]*"' | head -n 1)

            if [ ! -z "$PATH_DATA" ]; then
                echo "  <path id=\"layer-color-${counter}\" class=\"icon-part\" fill=\"$color\" $TRANSFORM_DATA $PATH_DATA />" >> "$target_svg"
            else
                echo "    [Aviso] El grupo $color no generó trazado."
            fi
            
            rm -f "temp_group_${counter}.bmp" "temp_group_${counter}.svg"
            counter=$((counter + 1))
        done
    fi
    
    echo "</svg>" >> "$target_svg"
    rm -f "temp_binary_map.bmp"

    echo "    [Debug] 5. Optimizando para web..."
    svgo "$target_svg" --multipass --output "$target_svg"

  # --- (El resto de los modos: Clásico, Color, Estándar se mantienen igual) ---
  elif [[ "$name" == *"_color"* ]]; then
     # ... (código existente del modo color) ...
     target_png="output/design/${name}_transparent.png"
     BG_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info:)
     $IMG_TOOL "$img" -alpha set -fuzz 20% -fill none -draw "color 0,0 floodfill" -fuzz 20% -fill none -draw "color $CENTER_X,$CENTER_Y floodfill" -fuzz 10% -transparent white -fuzz 10% -transparent "$BG_COLOR" -channel A -morphology Erode Disk:1.2 +channel -shave 1x1 -trim +repage "$target_png"
  elif [[ "$name" == *"_layers"* ]]; then
     # ... (código existente del modo capas clásico) ...
     target_svg="output/design/${name}.svg"
     $IMG_TOOL "$img" -fuzz 20% -fill white -draw "color 0,0 floodfill" -colorspace Gray -threshold 55% -morphology Close Disk:1 "temp_binary.bmp"
     CC_OUTPUT=$($IMG_TOOL "temp_binary.bmp" -define connected-components:verbose=true -define connected-components:area-threshold=5 -connected-components 4 null: | tr -d '\r')
     BLACK_IDS=$(echo "$CC_OUTPUT" | tail -n +2 | grep -iE "srgba\(0,0,0|srgb\(0,0,0|gray\(0|black|#000000" | awk '{print $1}' | sed 's/://')
     echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"
     if [ -n "$BLACK_IDS" ]; then
         COLORS=("#33CCFF" "#FF3366" "#33FF66" "#CC33FF" "#00FFFF")
         color_index=0
         counter=1
         for id in $BLACK_IDS; do
             CURRENT_COLOR="${COLORS[$color_index % ${#COLORS[@]}]}"
             REMOVE_LIST=""
             for other_id in $BLACK_IDS; do if [ "$other_id" != "$id" ]; then REMOVE_LIST="$REMOVE_LIST $other_id"; fi; done
             REMOVE_CSV=$(echo $REMOVE_LIST | xargs | tr ' ' ',')
             if [ -z "$REMOVE_CSV" ]; then cp "temp_binary.bmp" "temp_${counter}.bmp"; else $IMG_TOOL "temp_binary.bmp" -define connected-components:remove="${REMOVE_CSV}" -define connected-components:mean-color=true -connected-components 4 "temp_${counter}.bmp"; fi
             potrace "temp_${counter}.bmp" -s -o "temp_${counter}.svg"
             FLAT_SVG=$(tr '\n' ' ' < "temp_${counter}.svg")
             PATH_DATA=$(echo "$FLAT_SVG" | grep -o 'd="[^"]*"' | head -n 1)
             TRANSFORM_DATA=$(echo "$FLAT_SVG" | grep -o 'transform="[^"]*"' | head -n 1)
             if [ -n "$PATH_DATA" ]; then echo "  <path id=\"layer-${counter}\" class=\"icon-part\" fill=\"$CURRENT_COLOR\" $TRANSFORM_DATA $PATH_DATA />" >> "$target_svg"; fi
             rm -f "temp_${counter}.bmp" "temp_${counter}.svg"
             counter=$((counter + 1))
             color_index=$((color_index + 1))
         done
     fi
     echo "</svg>" >> "$target_svg"
     rm -f "temp_binary.bmp"
     svgo "$target_svg" --multipass --output "$target_svg"
  else
    target_svg="output/design/${name}.svg"
    generated_svg="$target_svg"
    $IMG_TOOL "$img" -fuzz 20% -fill white -draw "color 0,0 floodfill" -colorspace Gray -threshold 55% -morphology Close Disk:1 "${name}_bn.png"
    $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
    potrace "${name}.bmp" -s -o "$target_svg"
    rm -f "${name}_bn.png" "${name}.bmp"
  fi

  if [[ "$name" == *"_web"* && -n "$generated_svg" ]]; then
    svgo "$generated_svg" --multipass --output "output/web/${name}.min.svg"
  fi

  rm -f "$img"
done
