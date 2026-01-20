#!/bin/bash
set -e

mkdir -p output/web

for svg in output/design/*.svg; do
  [ -e "$svg" ] || continue
  name=$(basename "$svg" .svg)
  target="output/web/${name}.min.svg"

  # EFICIENCIA: Solo optimizar si el archivo minificado no existe
  if [ -f "$target" ]; then
    echo "Saltando $name: Ya existe versión optimizada."
    continue
  fi

  echo "Optimizando para web: $name..."
  svgo "$svg" --multipass --output "$target"
done