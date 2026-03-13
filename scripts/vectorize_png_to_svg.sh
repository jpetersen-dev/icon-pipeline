#!/bin/bash
set -e

# --- 1. CONFIGURACIÓN ---
if command -v magick >/dev/null 2>&1; then IMG_TOOL="magick"; IDENTIFY_TOOL="magick identify"
elif command -v convert >/dev/null 2>&1; then IMG_TOOL="convert"; IDENTIFY_TOOL="identify"
else echo "Error: ImageMagick no está instalado."; exit 1; fi

mkdir -p output/design; mkdir -p output/web; mkdir -p input/svg
shopt -s nullglob
FILES=(input/png/*.{png,jpg,jpeg,eps,PNG,JPG,JPEG,EPS} input/svg/*.{svg,SVG})

if [ ${#FILES[@]} -eq 0 ]; then exit 0; fi

# --- 2. PROCESAMIENTO ---
for img in "${FILES[@]}"; do
  filename=$(basename -- "$img")
  name="${filename%.*}"
  ext="${filename##*.}"
  ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  echo "----------------------------------------"
  echo "Procesando: $filename"

  # =====================================================================================
  # MODO CONVERSIÓN: Vector (SVG) a Raster (PNG) con Dimensiones Dinámicas
  # =====================================================================================
  if [ "$ext_lower" == "svg" ]; then
    echo "  -> Modo Conversión: Vector (SVG) a Raster (PNG)..."
    target_png="output/design/${name}.png"
    
    # 1. Tamaño Dinámico: Ancho Específico (_w500)
    if [[ "$name" =~ _w([0-9]+) ]]; then
        TARGET_W="${BASH_REMATCH[1]}"
        echo "    [Debug] Lienzo Dinámico: Ancho exacto de ${TARGET_W}px"
        $IMG_TOOL -density 300 -background none "$img" -trim +repage -resize "${TARGET_W}x" "$target_png"

    # 2. Tamaño Dinámico: Alto Específico (_h500)
    elif [[ "$name" =~ _h([0-9]+) ]]; then
        TARGET_H="${BASH_REMATCH[1]}"
        echo "    [Debug] Lienzo Dinámico: Alto exacto de ${TARGET_H}px"
        $IMG_TOOL -density 300 -background none "$img" -trim +repage -resize "x${TARGET_H}" "$target_png"

    # 3. Formato Cuadrado (Instagram Feed)
    elif [[ "$name" == *"_ig"* || "$name" == *"_sq"* ]]; then
        echo "    [Debug] Lienzo: 1080x1080 (Cuadrado)"
        $IMG_TOOL -background none "$img" -resize 1000x1000 -gravity center -extent 1080x1080 "$target_png"
        
    # 4. Formato Historia / Reel
    elif [[ "$name" == *"_story"* || "$name" == *"_reel"* ]]; then
        echo "    [Debug] Lienzo: 1080x1920 (Vertical)"
        $IMG_TOOL -background none "$img" -resize 1000x1800 -gravity center -extent 1080x1920 "$target_png"
        
    # 5. Formato Web Wide / Facebook Link
    elif [[ "$name" == *"_fb"* || "$name" == *"_wide"* ]]; then
        echo "    [Debug] Lienzo: 1200x630 (Horizontal)"
        $IMG_TOOL -background none "$img" -resize 1100x550 -gravity center -extent 1200x630 "$target_png"
        
    # 6. Formato Exacto / Tamaño Justo (Sin sufijo de tamaño)
    else
        echo "    [Debug] Lienzo: Tamaño exacto al contenido (Trim, Alta Resolución)"
        $IMG_TOOL -density 300 -background none "$img" -trim +repage "$target_png"
    fi
    
    rm -f "$img"
    continue
  fi
  
  # =====================================================================================
  # A PARTIR DE AQUÍ: MODOS CLÁSICOS DE RASTER A SVG
  # =====================================================================================
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  target_svg="output/design/${name}.svg"

  # --- MODO MULTICOLOR DINÁMICO ---
  if [[ "$name" == *"_layers"* || "$name" == *"_multicolor"* || "$name" =~ _color([1-8]) ]]; then
    if [[ "$name" =~ _color([1-8]) ]]; then MAX_COLORS="${BASH_REMATCH[1]}"; else MAX_COLORS=5; fi
    echo "  -> Modo Multicolor: Separación por canales ($MAX_COLORS colores)..."
    
    $IMG_TOOL "$img" -background white -alpha remove -colorspace sRGB -blur 0x0.3 +dither -colors 16 -normalize "temp_quantized.png"
    BG_HEX=$($IMG_TOOL "temp_quantized.png" -format "%[hex:p{0,0}]" info: | head -n 1 | cut -c 1-6)
    BG_COLOR="#${BG_HEX}"
    
    COLORS=$($IMG_TOOL "temp_quantized.png" -format "%c" histogram:info: | grep -iE '#[0-9A-Fa-f]{6}' | grep -ivE "$BG_COLOR|#FFFFFF|#FDFDFD|#FEFEFE|#FEFFFD|none" | sort -nr | head -n $MAX_COLORS | grep -oE '#[0-9A-Fa-f]{6}' || true)
    
    if [ -z "$COLORS" ]; then COLORS="#000000"; $IMG_TOOL "temp_quantized.png" -threshold 50% "temp_quantized.png"; fi

    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"
    
    counter=1
    for hex_color in $COLORS; do
        $IMG_TOOL "temp_quantized.png" -fuzz 8% -fill black -opaque "$hex_color" -fuzz 0% -fill white +opaque black -morphology Close Disk:1 "temp_layer.bmp"
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
    svgo "$target_svg" --multipass --output "$target_svg"

  # --- MODO BOLD ---
  elif [[ "$name" == *"_bold"* ]]; then
    echo "  -> Modo Bold: Vectorización monocromática con trazos engrosados..."
    CORNER_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info: | head -n 1)
    $IMG_TOOL "$img" -fuzz 20% -fill white -opaque "$CORNER_COLOR" -colorspace Gray -threshold 55% -morphology Erode Disk:1 "${name}_bn.png"
    $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
    potrace "${name}.bmp" -s -o "$target_svg"
    rm -f "${name}_bn.png" "${name}.bmp"

  # --- MODO TEXTURA ---
  elif [[ "$name" == *"_texture"* ]]; then
    echo "  -> Modo Textura: Tramado de semitonos..."
    $IMG_TOOL "$img" -background white -alpha remove -colorspace Gray -ordered-dither o8x8 "${name}_texture.bmp"
    potrace "${name}_texture.bmp" -s -o "$target_svg"
    rm -f "${name}_texture.bmp"

  # --- MODO ENHANCE ---
  elif [[ "$name" == *"_enhance"* ]]; then
    echo "  -> Modo Enhance: Escalado Lanczos, limpieza de ruido y nitidez..."
    target_img="output/design/${name}_enhanced.${ext}"
    $IMG_TOOL "$img" -filter Lanczos -resize 200% -enhance -noise 2 -unsharp 0x1.5+1.5+0.02 -modulate 105,110 -quality 95 "$target_img"

  # --- MODO COLOR PLANO (Transparente) ---
  elif [[ "$name" == *"_color"* ]]; then
     echo "  -> Modo Color: Limpieza de fondo transparente..."
     target_png="output/design/${name}_transparent.png"
     CORNER_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info: | head -n 1)
     $IMG_TOOL "$img" -alpha set -fuzz 15% -transparent "$CORNER_COLOR" -trim +repage "$target_png"

  # --- MODO ESTÁNDAR ---
  else
    echo "  -> Modo Estándar: Vectorización monocromática..."
    CORNER_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info: | head -n 1)
    $IMG_TOOL "$img" -fuzz 20% -fill white -opaque "$CORNER_COLOR" -colorspace Gray -threshold 55% -morphology Close Disk:1 "${name}_bn.png"
    $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
    potrace "${name}.bmp" -s -o "$target_svg"
    
    if [[ "$name" == *"_hole"* ]]; then rsvg-convert -f pdf -o "output/design/${name}_frame.pdf" "$target_svg"; fi
    rm -f "${name}_bn.png" "${name}.bmp"
  fi

  # Optimizador Web
  if [[ "$name" == *"_web"* && -f "output/design/${name}.svg" ]]; then
    svgo "output/design/${name}.svg" --multipass --output "output/web/${name}.min.svg"
  fi

  rm -f "$img"
done
