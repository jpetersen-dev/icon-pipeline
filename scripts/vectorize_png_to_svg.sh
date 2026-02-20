#!/bin/bash
set -e

# --- 1. CONFIGURACIÓN ---
if command -v magick >/dev/null 2>&1; then IMG_TOOL="magick"; IDENTIFY_TOOL="magick identify"
elif command -v convert >/dev/null 2>&1; then IMG_TOOL="convert"; IDENTIFY_TOOL="identify"
else echo "Error: ImageMagick no está instalado."; exit 1; fi

mkdir -p output/design; mkdir -p output/web
shopt -s nullglob
FILES=(input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS})

if [ ${#FILES[@]} -eq 0 ]; then exit 0; fi

# --- 2. PROCESAMIENTO ---
for img in "${FILES[@]}"; do
  filename=$(basename -- "$img")
  name="${filename%.*}"
  echo "----------------------------------------"
  echo "Procesando: $filename"
  
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  target_svg="output/design/${name}.svg"

  # =====================================================================================
  # MODO CAPAS HYBRIDO (LA LÓGICA PROBADA QUE FUNCIONÓ)
  # =====================================================================================
  if [[ "$name" == *"_layers"* || "$name" == *"_multicolor"* ]]; then
    echo "  -> Modo Híbrido: Separación geométrica + Agrupación por color real..."
    
    # 1. Reducir colores sobre fondo blanco (sin transparencias)
    $IMG_TOOL "$img" -background white -alpha remove +dither -colors 8 "temp_reduced_colors.png"

    # 2. Crear mapa binario garantizado: Fondo Blanco, Trazos Negros
    echo "    [Debug] Creando mapa de siluetas..."
    $IMG_TOOL "$img" -background white -alpha remove -fuzz 20% -fill white -draw "color 0,0 floodfill" -colorspace Gray -threshold 55% -morphology Close Disk:1 "temp_binary.bmp"

    # 3. Detectar topología
    echo "    [Debug] Analizando topología..."
    CC_OUTPUT=$($IMG_TOOL "temp_binary.bmp" -define connected-components:verbose=true -define connected-components:area-threshold=10 -connected-components 4 null: | tr -d '\r')
    
    # La pieza más grande siempre es el fondo (lo descartamos)
    BG_ID=$(echo "$CC_OUTPUT" | tail -n +2 | head -n 1 | awk '{print $1}' | sed 's/://')
    BLACK_IDS=$(echo "$CC_OUTPUT" | tail -n +2 | awk '{if ($1 != "'"$BG_ID"':" && $1 != "") print $1}' | sed 's/://')

    if [ -z "$BLACK_IDS" ]; then
         echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\"></svg>" > "$target_svg"
    else
        echo "    [Debug] Muestreando color original de cada pieza..."
        declare -A COLOR_GROUPS
        
        for id in $BLACK_IDS; do
            # LÓGICA DE MÁSCARA INFALIBLE (LA QUE FUNCIONÓ):
            REMOVE_LIST=""
            for other_id in $BLACK_IDS; do
                if [ "$other_id" != "$id" ]; then REMOVE_LIST="$REMOVE_LIST $other_id"; fi
            done
            REMOVE_CSV=$(echo $REMOVE_LIST | xargs | tr ' ' ',')

            if [ -z "$REMOVE_CSV" ]; then
                cp "temp_binary.bmp" "temp_mask_$id.bmp"
            else
                $IMG_TOOL "temp_binary.bmp" -define connected-components:remove="${REMOVE_CSV}" -define connected-components:mean-color=true -connected-components 4 "temp_mask_$id.bmp"
            fi

            $IMG_TOOL "temp_mask_$id.bmp" -negate "temp_mask_inv_$id.bmp"
            $IMG_TOOL "temp_reduced_colors.png" "temp_mask_inv_$id.bmp" -compose Multiply -composite "temp_color_$id.png"

            DOMINANT_COLOR=$($IMG_TOOL "temp_color_$id.png" -format "%c" histogram:info: | grep -iE '#[0-9a-fA-F]{6}' | grep -ivE '#000000|#FFFFFF|#FDFDFD|#FEFEFE|#F0F0F0|none' | sort -nr | head -n 1 | grep -m 1 -oE '#[0-9a-fA-F]{6}' || true)
            
            if [ -z "$DOMINANT_COLOR" ]; then DOMINANT_COLOR="#000000"; fi
            
            # echo "      - Isla $id -> Color detectado: $DOMINANT_COLOR" # Comentado para limpiar logs
            COLOR_GROUPS["$DOMINANT_COLOR"]="${COLOR_GROUPS["$DOMINANT_COLOR"]} $id"
            
            rm -f "temp_mask_$id.bmp" "temp_mask_inv_$id.bmp" "temp_color_$id.png"
        done

        echo "    [Debug] Vectorizando grupos consolidados de color..."
        echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"
        counter=1
        
        for hex_color in "${!COLOR_GROUPS[@]}"; do
            # Ignorar grupos negros (basura o errores de detección)
            if [ "$hex_color" == "#000000" ]; then continue; fi
            
            ids_to_keep="${COLOR_GROUPS[$hex_color]}"
            
            REMOVE_LIST=""
            for all_id in $BLACK_IDS; do
                keep_this=0
                for keep_id in $ids_to_keep; do
                    if [ "$all_id" == "$keep_id" ]; then keep_this=1; break; fi
                done
                if [ "$keep_this" -eq 0 ]; then REMOVE_LIST="$REMOVE_LIST $all_id"; fi
            done
            REMOVE_CSV=$(echo $REMOVE_LIST | xargs | tr ' ' ',')

            # CREAR LIENZO BLANCO SÓLIDO PARA EL GRUPO (LA SOLUCIÓN AL RECORTE)
            if [ -z "$REMOVE_CSV" ]; then
                cp "temp_binary.bmp" "temp_group_${counter}.bmp"
            else
                # Aislar las piezas y asegurar fondo blanco sólido
                $IMG_TOOL "temp_binary.bmp" -define connected-components:remove="${REMOVE_CSV}" -define connected-components:mean-color=true -connected-components 4 -background white -alpha remove "temp_group_${counter}.bmp"
            fi
            
            # Vectorizar (Potrace ama los fondos blancos sólidos)
            potrace "temp_group_${counter}.bmp" -s -o "temp_group_${counter}.svg"
            
            FLAT_SVG=$(tr '\n' ' ' < "temp_group_${counter}.svg")
            PATH_DATA=$(echo "$FLAT_SVG" | grep -m 1 -o 'd="[^"]*"' || true)
            TRANSFORM_DATA=$(echo "$FLAT_SVG" | grep -m 1 -o 'transform="[^"]*"' || true)

            if [ -n "$PATH_DATA" ]; then
                echo "  <path id=\"layer-color-${counter}\" class=\"icon-part\" fill=\"$hex_color\" $TRANSFORM_DATA $PATH_DATA />" >> "$target_svg"
            fi
            
            rm -f "temp_group_${counter}.bmp" "temp_group_${counter}.svg"
            counter=$((counter + 1))
        done
        echo "</svg>" >> "$target_svg"
    fi
    
    rm -f "temp_binary.bmp" "temp_reduced_colors.png"
    echo "    [Debug] Optimizando SVG final para Canva..."
    svgo "$target_svg" --multipass --output "$target_svg"

  # --- MODO COLOR PLANO ---
  elif [[ "$name" == *"_color"* ]]; then
     target_png="output/design/${name}_transparent.png"
     BG_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info:)
     $IMG_TOOL "$img" -alpha set -fuzz 20% -fill none -draw "color 0,0 floodfill" -fuzz 20% -fill none -draw "color $CENTER_X,$CENTER_Y floodfill" -fuzz 10% -transparent white -fuzz 10% -transparent "$BG_COLOR" -channel A -morphology Erode Disk:1.2 +channel -shave 1x1 -trim +repage "$target_png"

  # --- MODO ESTÁNDAR ---
  else
    target_svg="output/design/${name}.svg"
    $IMG_TOOL "$img" -fuzz 20% -fill white -draw "color 0,0 floodfill" -colorspace Gray -threshold 55% -morphology Close Disk:1 "${name}_bn.png"
    $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
    potrace "${name}.bmp" -s -o "$target_svg"
    if [[ "$name" == *"_hole"* ]]; then rsvg-convert -f pdf -o "output/design/${name}_frame.pdf" "$target_svg"; fi
    rm -f "${name}_bn.png" "${name}.bmp"
  fi

  if [[ "$name" == *"_web"* && -f "output/design/${name}.svg" ]]; then
    svgo "output/design/${name}.svg" --multipass --output "output/web/${name}.min.svg"
  fi

  rm -f "$img"
done
