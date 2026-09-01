#!/usr/bin/env bash
# Downloads ainergiz/medasr-mlx-fp16 weights into the app resource folder
# or Application Support (first-launch fallback is also in MedASREngine).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/RadiologySuite/Resources/MedASR-MLX"
mkdir -p "$DEST"
BASE="https://huggingface.co/ainergiz/medasr-mlx-fp16/resolve/main"
echo "Downloading MedASR MLX FP16 into $DEST"
curl -L "$BASE/config.json" -o "$DEST/config.json"
curl -L "$BASE/tokenizer.json" -o "$DEST/tokenizer.json" || true
curl -L "$BASE/weights.npz" -o "$DEST/weights.npz"
echo "Done. weights.npz size: $(wc -c < "$DEST/weights.npz") bytes"
