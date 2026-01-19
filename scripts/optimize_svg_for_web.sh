#!/bin/bash
set -e

mkdir -p output/web

for svg in output/design/*.svg; do
  name=$(basename "$svg" .svg)

  svgo "$svg" \
    --multipass \
    --output "output/web/${name}.min.svg"
done
