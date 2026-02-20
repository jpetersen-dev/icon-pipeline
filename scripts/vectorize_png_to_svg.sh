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
  # NUEVA ESTRATEGIA: SEPARACIÓN POR CANALES DE COLOR (Tipo Serigrafía)
  # =====================================================================================
  if [[ "$name" == *"_layers"* || "$name" == *"_multicolor"* ]]; then
    echo "  -> Nueva Estrategia: Separación por canales de color puro..."
    
    # 1. Aplanar y reducir paleta
    $IMG_TOOL "$img" -background white -alpha remove -colorspace sRGB -blur 0x0.3 +dither -colors 6 -normalize "temp_quantized.png"
    
    # 2. Obtenemos el HEX exacto del fondo (mirando el píxel de la esquina superior izquierda)
    BG_HEX=$($IMG_TOOL "temp_quantized.png" -format "%[hex:p{0,0}]" info: | head -n 1 | cut -c 1-6)
    BG_COLOR="#${BG_HEX}"
    echo "    [Debug] Fondo detectado y neutralizado: $BG_COLOR"
    
    # 3. Extraemos el histograma. 
    # Ordenamos de mayor a menor uso.
    # Ignoramos el color de fondo exacto y blancos puros.
    # Tomamos SOLO los 2 colores más abundantes (esto elimina el blanco sucio y los artefactos grises).
    echo "    [Debug] Extrayendo los 2 colores principales..."
    COLORS=$($IMG_TOOL "temp_quantized.png" -format "%c" histogram:info: | grep -iE '#[0-9A-Fa-f]{6}' | grep -ivE "$BG_COLOR|#FFFFFF|#FDFDFD|#FEFEFE|#FEFFFD|none" | sort -nr | head -n 2 | grep -oE '#[0-9A-Fa-f]{6}' || true)
    
    if [ -z "$COLORS" ]; then
        echo "    [Aviso] No se detectaron colores. Procesando como monocromático."
        COLORS="#000000"
        $IMG_TOOL "temp_quantized.png" -threshold 50% "temp_quantized.png"
    fi

    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"
    
    counter=1
    for hex_color in $COLORS; do
        echo "      - Vectorizando capa pura para el color: $hex_color"
        
        # Seleccionamos nuestro color objetivo y lo pintamos de NEGRO.
        # Pintamos el resto (fondo y el otro color) de BLANCO. Potrace recorta todo lo blanco.
        $IMG_TOOL "temp_quantized.png" -fuzz 2% -fill black -opaque "$hex_color" -fuzz 0% -fill white +opaque black -morphology Close Disk:1 "temp_layer.bmp"
        
        potrace "temp_layer.bmp" -s -o "temp_layer.svg"
        
        FLAT_SVG=$(tr '\n' ' ' < "temp_layer.svg")
        TRANSFORM_DATA=$(echo "$FLAT_SVG" | grep -m 1 -o 'transform="[^"]*"' || true)
        
        echo "$FLAT_SVG" | grep -o 'd="[^"]*"' > "temp_paths.txt" || true
        
        path_count=1
        while read -r d_attr; do
            if [ -n "$d_attr" ]; then
                echo "  <path id=\"layer-${counter}-p-${path_count}\" class=\"icon-part\" fill=\"$hex_color\" $TRANSFORM_DATA $d_attr />" >> "$target_svg"
                path_count=$((path_count + 1))
            fi
        done < "temp_paths.txt"
        
        rm -f "temp_layer.bmp" "temp_layer.svg" "temp_paths.txt"
        counter=$((counter + 1))
    done
    echo "</svg>" >> "$target_svg"
    
    rm -f "temp_quantized.png"
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
