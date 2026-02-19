#!/bin/bash
set -e

mkdir -p output/web

echo "Iniciando optimización web masiva..."

shopt -s nullglob
FILES=(output/design/*.svg)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No se encontraron SVGs en output/design/ para optimizar."
  exit 0
fi

for svg in "${FILES[@]}"; do
  name=$(basename "$svg" .svg)
  target="output/web/${name}.min.svg"

  # EFICIENCIA: Solo salta si el archivo existe Y NO estamos forzando la actualización
  if [ -f "$target" ] && [ "$FORCE_ALL" != "true" ]; then
    echo "Saltando $name: Ya existe versión optimizada."
    continue
  fi

  echo "Optimizando para web: $name..."
  svgo "$svg" --multipass --output "$target"
done

echo "Proceso de optimización masiva finalizado."