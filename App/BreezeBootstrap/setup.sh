#!/bin/bash
set -eu
source "$(dirname "$0")/environment.sh"
export PATH="$BREEZE_ROOT/tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
mkdir "$BREEZE_ROOT/data/install.lock" 2>/dev/null || { echo '已有安装任务运行；若上次异常退出，请检查后移除 data/install.lock'; exit 1; }
staging=""
cleanup() {
    if [ -n "$staging" ]; then rm -rf "$staging"; fi
    rmdir "$BREEZE_ROOT/data/install.lock"
}
trap cleanup EXIT
if curl --silent --max-time 2 --fail http://127.0.0.1:17860/health >/dev/null; then
    echo '请先在语音合成页停止服务，再安装或修复环境。'; exit 1
fi
staging="$(mktemp -d "$TMPDIR/install.XXXXXX")"
if ! command -v uv >/dev/null; then
    echo '正在从 Astral 官方安装 uv（仅放入当前目录，不修改系统 PATH）…'
    curl --fail --location --retry 3 https://astral.sh/uv/install.sh -o "$staging/install-uv.sh"
    UV_UNMANAGED_INSTALL="$BREEZE_ROOT/tools" UV_NO_MODIFY_PATH=1 bash "$staging/install-uv.sh"
fi
revision=f1818ec44da33302701718e5fb15267ce1cf5e4f
runtime="$BREEZE_ROOT/runtime"
if [ "$(cat "$runtime/.source-revision" 2>/dev/null || true)" != "$revision" ] \
    || [ ! -f "$runtime/breeze_infer/api.py" ] || [ ! -d "$runtime/models" ] \
    || [ ! -f "$runtime/configs/fast.json" ] || [ ! -f "$runtime/LICENSE" ] \
    || [ ! -f "$runtime/requirements.txt" ] || [ ! -f "$runtime/requirements-mac-overrides.txt" ]; then
    echo '正在下载 Breeze 服务代码…'
    git clone --no-checkout https://github.com/Shoofio/breeze-tts2-fast-streaming-api.git "$staging/source"
    # Export runtime files only; upstream tests, docs and Git history stay out of app data.
    git -C "$staging/source" archive "$revision" breeze_infer models configs LICENSE \
        requirements.txt requirements-mac-overrides.txt > "$staging/runtime.tar"
    mkdir -p "$runtime"
    tar -xf "$staging/runtime.tar" -C "$runtime"
    printf '%s\n' "$revision" > "$runtime/.source-revision"
fi
cd "$runtime"
# The upstream manifest also includes development tools; the app does not run them.
awk '!/^(pytest|ruff)([<>=!~[:space:]]|$)/' requirements.txt > "$staging/requirements.txt"
echo '正在安装 Python 3.12 与 MLX 依赖…'
uv venv --python 3.12 --allow-existing
uv pip install -r "$staging/requirements.txt" --overrides requirements-mac-overrides.txt
echo '正在下载模型（约 7 GB，可重试）…'
"$runtime/.venv/bin/hf" download mlx-community/Breeze-TTS-2-mlx --revision 3c8829fb7fd335818f085cd2ef49b4100c0e46c8
echo '安装完成，请启动本地服务。'
