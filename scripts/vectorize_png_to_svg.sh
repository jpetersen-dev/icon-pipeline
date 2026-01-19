#!/bin/bash
set -e

mkdir -p output/design

for img in input/png/*.png; do
  name=$(basename "$img" .png)

  magick "$img" \
    -alpha set \
    -fuzz 15% \
    -fill none \
    -draw "color 0,0 floodfill" \
    -colorspace Gray \
    -threshold 50% \
    -morphology Dilate Diamond:1 \
    "${name}_bn.png"

  magick "${name}_bn.png" "${name}.bmp"

  potrace "${name}.bmp" -s -o "output/design/${name}.svg"

  rm "${name}_bn.png" "${name}.bmp"
done
