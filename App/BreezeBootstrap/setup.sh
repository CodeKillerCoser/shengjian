#!/bin/bash
set -eu
source "$(dirname "$0")/environment.sh"
export PATH="$BREEZE_ROOT/tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
mkdir "$BREEZE_ROOT/data/install.lock" 2>/dev/null || { echo '已有安装任务运行；若上次异常退出，请检查后移除 data/install.lock'; exit 1; }
trap 'rmdir "$BREEZE_ROOT/data/install.lock"' EXIT
if curl --silent --max-time 2 --fail http://127.0.0.1:17860/health >/dev/null; then
    echo '请先在语音合成页停止服务，再安装或修复环境。'; exit 1
fi
if ! command -v uv >/dev/null; then
    echo '正在从 Astral 官方安装 uv（仅放入当前目录，不修改系统 PATH）…'
    curl --fail --location --retry 3 https://astral.sh/uv/install.sh -o "$TMPDIR/install-uv.sh"
    UV_UNMANAGED_INSTALL="$BREEZE_ROOT/tools" UV_NO_MODIFY_PATH=1 bash "$TMPDIR/install-uv.sh"
fi
if [ ! -d "$BREEZE_ROOT/runtime/.git" ]; then
    echo '正在下载 Breeze 服务代码…'
    git clone https://github.com/Shoofio/breeze-tts2-fast-streaming-api.git "$BREEZE_ROOT/runtime"
    git -C "$BREEZE_ROOT/runtime" checkout f1818ec44da33302701718e5fb15267ce1cf5e4f
fi
cd "$BREEZE_ROOT/runtime"
echo '正在安装 Python 3.12 与 MLX 依赖…'
uv venv --python 3.12 --allow-existing
uv pip install -r requirements.txt --overrides requirements-mac-overrides.txt
echo '正在下载模型（约 7 GB，可重试）…'
uvx --from huggingface_hub hf download mlx-community/Breeze-TTS-2-mlx --revision 3c8829fb7fd335818f085cd2ef49b4100c0e46c8
echo '安装完成，请启动本地服务。'
