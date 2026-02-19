#!/bin/bash
set -e

# --- 1. CONFIGURACIÓN ---
if command -v magick >/dev/null 2>&1; then IMG_TOOL="magick"; IDENTIFY_TOOL="magick identify"
elif command -v convert >/dev/null 2>&1; then IMG_TOOL="convert"; IDENTIFY_TOOL="identify"
else echo "Error: ImageMagick no está instalado."; exit 1; fi

mkdir -p output/design; mkdir -p output/web
shopt -s nullglob
FILES=(input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS})

if [ ${#FILES[@]} -eq 0 ]; then echo "No hay imágenes nuevas."; exit 0; fi

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
  # MODO CAPAS HYBRIDO (LA SOLUCIÓN DEFINITIVA)
  # Combina separación geométrica perfecta con agrupación por color real.
  # =====================================================================================
  if [[ "$name" == *"_layers"* || "$name" == *"_multicolor"* ]]; then
    echo "  -> Modo Híbrido: Separación geométrica + Agrupación por color real..."
    
    # 1. PREPARACIÓN DE LA IMAGEN ORIGINAL
    # Reducimos la imagen a color a una paleta muy estricta (ej. 4 colores) para evitar
    # que el antialiasing genere miles de tonos de rojo/azul distintos.
    $IMG_TOOL "$img" +dither -colors 4 "temp_reduced_colors.png"

    # 2. GENERACIÓN DEL MAPA BINARIO (GEOMETRÍA)
    echo "    [Debug] Creando mapa de siluetas para detectar islas..."
    $IMG_TOOL "temp_reduced_colors.png" \
      -fuzz 20% -fill white -draw "color 0,0 floodfill" \
      -colorspace Gray -threshold 55% -morphology Close Disk:1 \
      "temp_binary.bmp"

    # 3. DETECCIÓN DE ISLAS (PIEZAS SUELTAS)
    echo "    [Debug] Analizando topología y separando piezas..."
    CC_OUTPUT=$($IMG_TOOL "temp_binary.bmp" -define connected-components:verbose=true -define connected-components:area-threshold=10 -connected-components 4 null: | tr -d '\r')
    
    # IDs de todo lo que no sea blanco (fondo)
    BLACK_IDS=$(echo "$CC_OUTPUT" | tail -n +2 | grep -ivE "white|#FFFFFF|gray\(255\)" | awk '{print $1}' | sed 's/://')

    if [ -z "$BLACK_IDS" ]; then
         echo "    [Alerta] No se detectaron piezas para vectorizar."
         echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\"></svg>" > "$target_svg"
    else
        echo "    [Debug] Muestreando color original de cada pieza..."
        
        # Array asociativo para agrupar IDs por su código HEX de color real
        declare -A COLOR_GROUPS
        
        for id in $BLACK_IDS; do
            # Crear máscara de SOLO esta pieza
            $IMG_TOOL "temp_binary.bmp" -define connected-components:keep="$id" -connected-components 4 "temp_mask_$id.bmp"
            
            # Usar la máscara sobre la imagen de color reducida para encontrar el color predominante
            # El '|| true' evita que el script muera si grep no encuentra nada.
            DOMINANT_COLOR=$($IMG_TOOL "temp_reduced_colors.png" "temp_mask_$id.bmp" -alpha off -compose CopyOpacity -composite -format "%c" histogram:info: | grep -ivE 'none|#00000000|#FFFFFF' | sort -nr | head -n 1 | grep -oE '#[0-9a-fA-F]{6}' || true)
            
            # Si falla la detección, asignar un gris neutro por defecto para no romper el grupo
            if [ -z "$DOMINANT_COLOR" ]; then DOMINANT_COLOR="#808080"; fi
            
            # Agrupar el ID bajo su color detectado
            COLOR_GROUPS["$DOMINANT_COLOR"]="${COLOR_GROUPS["$DOMINANT_COLOR"]} $id"
            rm -f "temp_mask_$id.bmp"
        done

        # 4. VECTORIZACIÓN Y ENSAMBLADO FINAL POR GRUPOS DE COLOR
        echo "    [Debug] Vectorizando grupos de color..."
        echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"
        counter=1
        
        # Iterar sobre los colores HEX únicos encontrados
        for hex_color in "${!COLOR_GROUPS[@]}"; do
            # Obtener la lista de IDs que pertenecen a este color
            ids_to_keep=$(echo ${COLOR_GROUPS[$hex_color]} | xargs | tr ' ' ',')
            echo "      - Procesando capa color $hex_color (Piezas: $ids_to_keep)"
            
            # Crear un mapa binario que contiene SOLO las piezas de este color
            $IMG_TOOL "temp_binary.bmp" \
              -define connected-components:keep="$ids_to_keep" \
              -connected-components 4 \
              "temp_group_${counter}.bmp"
              
            # Vectorizar el grupo. Potrace manejará perfectamente los huecos.
            potrace "temp_group_${counter}.bmp" -s -o "temp_group_${counter}.svg"
            
            # Aplanar y extraer el trazado para Canva
            FLAT_SVG=$(tr '\n' ' ' < "temp_group_${counter}.svg")
            PATH_DATA=$(echo "$FLAT_SVG" | grep -o 'd="[^"]*"' | head -n 1 || true)
            TRANSFORM_DATA=$(echo "$FLAT_SVG" | grep -o 'transform="[^"]*"' | head -n 1 || true)

            if [ -n "$PATH_DATA" ]; then
                echo "  <path id=\"layer-color-${counter}\" class=\"icon-part\" fill=\"$hex_color\" $TRANSFORM_DATA $PATH_DATA />" >> "$target_svg"
            fi
            rm -f "temp_group_${counter}.bmp" "temp_group_${counter}.svg"
            counter=$((counter + 1))
        done
        echo "</svg>" >> "$target_svg"
    fi
    
    # Limpieza final
    rm -f "temp_binary.bmp" "temp_reduced_colors.png"
    echo "    [Debug] Optimizando SVG final para Canva..."
    svgo "$target_svg" --multipass --output "$target_svg"

  # --- OTROS MODOS (Para mantener compatibilidad) ---
  elif [[ "$name" == *"_color"* ]]; then
     # (Modo color simple para imágenes planas sin capas)
     target_png="output/design/${name}_transparent.png"
     BG_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info:)
     $IMG_TOOL "$img" -alpha set -fuzz 20% -fill none -draw "color 0,0 floodfill" -fuzz 20% -fill none -draw "color $CENTER_X,$CENTER_Y floodfill" -fuzz 10% -transparent white -fuzz 10% -transparent "$BG_COLOR" -channel A -morphology Erode Disk:1.2 +channel -shave 1x1 -trim +repage "$target_png"
  else
    # (Modo estándar B/N)
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
