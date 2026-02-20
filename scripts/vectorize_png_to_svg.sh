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
  # MODO CAPAS HYBRIDO (MUESTRO PERFECTO + HUECOS GARANTIZADOS + EXTRACCIÓN TOTAL)
  # =====================================================================================
  if [[ "$name" == *"_layers"* || "$name" == *"_multicolor"* ]]; then
    echo "  -> Modo Híbrido: Analizando geometría y colores..."
    
    # Reducir colores sobre fondo blanco
    $IMG_TOOL "$img" -background white -alpha remove +dither -colors 8 "temp_reduced_colors.png"

    # Crear mapa binario perfecto
    $IMG_TOOL "$img" -background white -alpha remove -fuzz 20% -fill white -draw "color 0,0 floodfill" -colorspace Gray -threshold 55% -morphology Close Disk:1 "temp_binary.bmp"

    # Analizar topología para separar piezas y aislar huecos
    echo "    [Debug] Analizando topología y aislando huecos..."
    CC_OUTPUT=$($IMG_TOOL "temp_binary.bmp" -define connected-components:verbose=true -define connected-components:area-threshold=10 -connected-components 4 null: | tr -d '\r')
    
    BG_COLOR_RAW=$(echo "$CC_OUTPUT" | tail -n +2 | head -n 1 | awk '{print $NF}')
    
    # LA CLAVE DE LOS HUECOS: Guardamos TODOS los IDs de las zonas blancas
    WHITE_CSV=$(echo "$CC_OUTPUT" | tail -n +2 | awk -v bgc="$BG_COLOR_RAW" '{if ($NF == bgc) print $1}' | sed 's/://' | xargs | tr ' ' ',')
    # Extraemos solo los IDs de las piezas negras
    BLACK_IDS=$(echo "$CC_OUTPUT" | tail -n +2 | awk -v bgc="$BG_COLOR_RAW" '{if ($NF != bgc) print $1}' | sed 's/://')

    if [ -z "$BLACK_IDS" ]; then
         echo "    [Alerta] No se detectaron piezas."
         echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\"></svg>" > "$target_svg"
    else
        echo "    [Debug] Muestreando color original..."
        declare -A COLOR_GROUPS
        
        for id in $BLACK_IDS; do
            # 1. Aislar manteniendo los huecos explícitamente (KEEP)
            KEEP_ALL="${id},${WHITE_CSV}"
            KEEP_ALL=$(echo "$KEEP_ALL" | sed 's/,$//' | sed 's/^,//')
            
            $IMG_TOOL "temp_binary.bmp" -define connected-components:mean-color=true -define connected-components:keep="$KEEP_ALL" -connected-components 4 "temp_mask_$id.bmp"
            
            # 2. Invertir y Multiplicar
            $IMG_TOOL "temp_mask_$id.bmp" -negate "temp_mask_inv_$id.bmp"
            $IMG_TOOL "temp_reduced_colors.png" "temp_mask_inv_$id.bmp" -compose Multiply -composite "temp_color_$id.png"

            # 3. Muestrear (ignorando el negro absoluto)
            DOMINANT_COLOR=$($IMG_TOOL "temp_color_$id.png" -format "%c" histogram:info: | grep -ivE 'none|#000000|#00000000' | sort -nr | head -n 1 | grep -m 1 -oE '#[0-9a-fA-F]{6}' || true)
            
            if [ -z "$DOMINANT_COLOR" ]; then DOMINANT_COLOR="#000000"; fi
            
            echo "      - Pieza $id -> Color detectado: $DOMINANT_COLOR"
            COLOR_GROUPS["$DOMINANT_COLOR"]="${COLOR_GROUPS["$DOMINANT_COLOR"]} $id"
            
            rm -f "temp_mask_$id.bmp" "temp_mask_inv_$id.bmp" "temp_color_$id.png"
        done

        num_colors=${#COLOR_GROUPS[@]}
        echo "    [Debug] Colores únicos a generar: $num_colors"
        echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"
        
        counter=1
        for hex_color in "${!COLOR_GROUPS[@]}"; do
            ids_to_keep="${COLOR_GROUPS[$hex_color]}"
            ids_csv=$(echo $ids_to_keep | xargs | tr ' ' ',')
            
            # LA CLAVE DE LOS HUECOS EN LA AGRUPACIÓN
            KEEP_ALL="${ids_csv},${WHITE_CSV}"
            KEEP_ALL=$(echo "$KEEP_ALL" | sed 's/,$//' | sed 's/^,//')
            
            $IMG_TOOL "temp_binary.bmp" -define connected-components:mean-color=true -define connected-components:keep="$KEEP_ALL" -connected-components 4 "temp_group_${counter}.bmp"
            potrace "temp_group_${counter}.bmp" -s -o "temp_group_${counter}.svg"
            
            FLAT_SVG=$(tr '\n' ' ' < "temp_group_${counter}.svg")
            TRANSFORM_DATA=$(echo "$FLAT_SVG" | grep -m 1 -o 'transform="[^"]*"' || true)

            # LA SOLUCIÓN A LAS PIEZAS FALTANTES: Un bucle que extrae TODOS los trazados generados
            echo "$FLAT_SVG" | grep -o 'd="[^"]*"' > "temp_paths.txt" || true
            
            path_count=1
            while read -r d_attr; do
                if [ -n "$d_attr" ]; then
                    echo "  <path id=\"layer-${counter}-piece-${path_count}\" class=\"icon-part\" fill=\"$hex_color\" $TRANSFORM_DATA $d_attr />" >> "$target_svg"
                    path_count=$((path_count + 1))
                fi
            done < "temp_paths.txt"
            
            rm -f "temp_group_${counter}.bmp" "temp_group_${counter}.svg" "temp_paths.txt"
            counter=$((counter + 1))
        done
        echo "</svg>" >> "$target_svg"
    fi
    
    rm -f "temp_binary.bmp" "temp_reduced_colors.png"
    echo "    [Debug] Optimizando SVG..."
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
