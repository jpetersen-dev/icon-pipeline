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
  ext="${filename##*.}"
  echo "----------------------------------------"
  echo "Procesando: $filename"
  
  DIMENSIONS=$($IDENTIFY_TOOL -format "%w %h" "$img")
  WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
  HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
  target_svg="output/design/${name}.svg"

  # =====================================================================================
  # MODO MULTICOLOR DINÁMICO (Soporta _layers, _multicolor, o _color1 hasta _color8)
  # =====================================================================================
  if [[ "$name" == *"_layers"* || "$name" == *"_multicolor"* || "$name" =~ _color([1-8]) ]]; then
    
    # Extraemos el número dinámicamente si se usó el formato _colorX
    if [[ "$name" =~ _color([1-8]) ]]; then
        MAX_COLORS="${BASH_REMATCH[1]}"
    else
        MAX_COLORS=5 # Límite por defecto si solo se usa _layers o _multicolor
    fi
    
    echo "  -> Modo Multicolor: Separación por canales ($MAX_COLORS colores)..."
    
    # Ampliamos la paleta inicial a 16 colores para no perder tonos sutiles antes del filtrado
    $IMG_TOOL "$img" -background white -alpha remove -colorspace sRGB -blur 0x0.3 +dither -colors 16 -normalize "temp_quantized.png"
    BG_HEX=$($IMG_TOOL "temp_quantized.png" -format "%[hex:p{0,0}]" info: | head -n 1 | cut -c 1-6)
    BG_COLOR="#${BG_HEX}"
    
    # El 'head -n $MAX_COLORS' es la barrera dinámica
    COLORS=$($IMG_TOOL "temp_quantized.png" -format "%c" histogram:info: | grep -iE '#[0-9A-Fa-f]{6}' | grep -ivE "$BG_COLOR|#FFFFFF|#FDFDFD|#FEFEFE|#FEFFFD|none" | sort -nr | head -n $MAX_COLORS | grep -oE '#[0-9A-Fa-f]{6}' || true)
    
    if [ -z "$COLORS" ]; then COLORS="#000000"; $IMG_TOOL "temp_quantized.png" -threshold 50% "temp_quantized.png"; fi

    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"
    
    counter=1
    for hex_color in $COLORS; do
        echo "      - Vectorizando capa pura para el color: $hex_color"
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
    svgo "$target_svg" --multipass --output "$target_svg"

  # =====================================================================================
  # MODO TEXTURA / SOMBRAS (Tramado de Semitonos Vectorial)
  # =====================================================================================
  elif [[ "$name" == *"_texture"* ]]; then
    echo "  -> Modo Textura: Tramado de semitonos (Halftone Dithering)..."
    target_svg="output/design/${name}.svg"
    
    # Convierte degradados en patrones de puntos perfectos para vectorizar
    $IMG_TOOL "$img" -background white -alpha remove -colorspace Gray -ordered-dither o8x8 "${name}_texture.bmp"
    potrace "${name}_texture.bmp" -s -o "$target_svg"
    rm -f "${name}_texture.bmp"

  # =====================================================================================
  # MODO ENHANCE (Mejorador de Fotos con IA Matemática)
  # =====================================================================================
  elif [[ "$name" == *"_enhance"* ]]; then
    echo "  -> Modo Enhance: Escalado Lanczos, limpieza de ruido y nitidez..."
    target_img="output/design/${name}_enhanced.${ext}"
    
    $IMG_TOOL "$img" -filter Lanczos -resize 200% -enhance -noise 2 -unsharp 0x1.5+1.5+0.02 -modulate 105,110 -quality 95 "$target_img"

  # =====================================================================================
  # MODO COLOR PLANO (Limpieza de Fondo Raster - PNG)
  # =====================================================================================
  elif [[ "$name" == *"_color"* ]]; then
     echo "  -> Modo Color: Limpieza de fondo transparente..."
     target_png="output/design/${name}_transparent.png"
     CORNER_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info: | head -n 1)
     $IMG_TOOL "$img" -alpha set -fuzz 15% -transparent "$CORNER_COLOR" -trim +repage "$target_png"

  # =====================================================================================
  # MODO ESTÁNDAR (Blanco y Negro Vectorial Clásico - Siluetas)
  # =====================================================================================
  else
    echo "  -> Modo Estándar: Vectorización monocromática de alto contraste..."
    target_svg="output/design/${name}.svg"
    CORNER_COLOR=$($IMG_TOOL "$img" -format "%[pixel:p{0,0}]" info: | head -n 1)
    $IMG_TOOL "$img" -fuzz 20% -fill white -opaque "$CORNER_COLOR" -colorspace Gray -threshold 55% -morphology Close Disk:1 "${name}_bn.png"
    $IMG_TOOL "${name}_bn.png" -background white -alpha remove "${name}.bmp"
    potrace "${name}.bmp" -s -o "$target_svg"
    
    if [[ "$name" == *"_hole"* ]]; then 
        echo "    [Debug] Generando PDF de corte (_hole)..."
        rsvg-convert -f pdf -o "output/design/${name}_frame.pdf" "$target_svg"
    fi
    rm -f "${name}_bn.png" "${name}.bmp"
  fi

  # Optimizador Web
  if [[ "$name" == *"_web"* && -f "output/design/${name}.svg" ]]; then
    echo "    [Debug] Generando versión web comprimida..."
    svgo "output/design/${name}.svg" --multipass --output "output/web/${name}.min.svg"
  fi

  rm -f "$img"
done