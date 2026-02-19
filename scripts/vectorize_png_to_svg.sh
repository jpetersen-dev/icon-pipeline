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

# Configuración segura para que no falle si la carpeta input está vacía
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

  # Variable para rastrear si se generó un SVG en este ciclo
  generated_svg=""

  # --- MODO COLOR: Limpieza de "islas" blancas ---
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
    
  # --- MODO CAPAS: Separación de elementos para CSS ---
  elif [[ "$name" == *"_layers"* ]]; then
    echo "  -> Modo Capas: Separando elementos para $filename..."
    target_svg="output/design/${name}.svg"
    generated_svg="$target_svg"
    
    echo "    [Debug] Generando mapa binario..."
    # 1. Limpiamos y binarizamos (asegura blanco y negro puro)
    $IMG_TOOL "$img" -fuzz 20% -fill white -draw "color 0,0 floodfill" \
      -colorspace Gray -threshold 55% -morphology Close Disk:1 "temp_binary.bmp"

    echo "    [Debug] Analizando topología..."
    # Obtenemos el análisis completo eliminando retornos de carro molestos
    CC_OUTPUT=$($IMG_TOOL "temp_binary.bmp" -define connected-components:verbose=true -define connected-components:area-threshold=5 -connected-components 4 null: | tr -d '\r')
    
    # --- DEBUG CRÍTICO: Imprimir lo que ve ImageMagick ---
    echo "    [DEBUG RAW OUTPUT] Inicio >>>"
    echo "$CC_OUTPUT"
    echo "    [DEBUG RAW OUTPUT] <<< Fin"
    # ----------------------------------------------------

    # 2. Detección robusta (Lógica Inversa)
    # Detectamos el ID del fondo blanco (buscando 'white', '255' o el color más frecuente)
    BG_ID=$(echo "$CC_OUTPUT" | tail -n +2 | grep -iE "white|#FFFFFF|255|,255,255\)" | head -n 1 | awk '{print $1}' | sed 's/://')

    # Obtenemos TODOS los IDs detectados
    ALL_IDS=$(echo "$CC_OUTPUT" | tail -n +2 | awk '{print $1}' | sed 's/://')

    # Filtramos: Los objetos son todo lo que NO sea el fondo
    OBJECT_IDS=""
    for id in $ALL_IDS; do
        # Si el ID actual no es el fondo (y no está vacío), lo agregamos a la lista
        if [ "$id" != "$BG_ID" ] && [ ! -z "$id" ]; then
            OBJECT_IDS="$OBJECT_IDS $id"
        fi
    done

    echo "    [Debug] ID del Fondo detectado: '$BG_ID'"
    echo "    [Debug] IDs de Piezas a procesar: $OBJECT_IDS"

    # Iniciamos el documento SVG
    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $WIDTH $HEIGHT\">" > "$target_svg"

    if [ -z "$OBJECT_IDS" ]; then
         echo "    [Alerta] No se detectaron piezas separadas del fondo."
    else
        counter=1
        for id in $OBJECT_IDS; do
            echo "    [Debug] Procesando capa ID: $id"
            
            # 3. AISLAMIENTO: Conservamos fondo y pieza
            $IMG_TOOL "temp_binary.bmp" \
              -define connected-components:keep="${BG_ID},${id}" \
              -define connected-components:mean-color=true \
              -connected-components 4 \
              "temp_${counter}.bmp"
              
            potrace "temp_${counter}.bmp" -s -o "temp_${counter}.svg"
            
            # 4. EXTRACCIÓN SEGURA MULTILÍNEA
            G_BLOCK=$(sed -n '/<g transform=/,/<\/g>/p' "temp_${counter}.svg")
            
            if [ ! -z "$G_BLOCK" ]; then
                echo "  " >> "$target_svg"
                echo "  <g class=\"layer icon-part-${counter}\">" >> "$target_svg"
                echo "$G_BLOCK" >> "$target_svg"
                echo "  </g>" >> "$target_svg"
            else
                echo "    [Aviso] La pieza $id falló al vectorizar o estaba vacía."
            fi
            
            rm -f "temp_${counter}.bmp" "temp_${counter}.svg"
            ((counter++))
        done
    fi
    
    echo "</svg>" >> "$target_svg"
    rm -f "temp_binary.bmp"

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

  # Limpiar imagen original de la carpeta input
  rm -f "$img"
done
