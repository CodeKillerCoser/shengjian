#!/bin/bash
set -eu
source "$(dirname "$0")/environment.sh"
cd "$BREEZE_ROOT/runtime"
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
exec "$BREEZE_ROOT/runtime/.venv/bin/python" -m breeze_infer.api \
 "$HF_HOME/hub/models--mlx-community--Breeze-TTS-2-mlx/snapshots/3c8829fb7fd335818f085cd2ef49b4100c0e46c8" \
 --host 127.0.0.1 --port 17860 --ws-port disabled --voices-dir "$BREEZE_ROOT/voices" --chunk-first 1 --chunk-max 1
