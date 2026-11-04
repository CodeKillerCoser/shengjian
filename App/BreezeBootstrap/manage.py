#!/usr/bin/env python3
import os, signal, subprocess, sys, pathlib
root = pathlib.Path(__file__).resolve().parent
pidfile = root / 'data/service.pid'
def active():
    try:
        pid = int(pidfile.read_text())
        command = subprocess.check_output(['/bin/ps', '-p', str(pid), '-o', 'command='], text=True)
        return pid if str(root) in command and ('breeze_infer.api' in command or 'start.sh' in command) else None
    except (OSError, ValueError, subprocess.CalledProcessError):
        return None
if sys.argv[1] == 'start':
    model = root/'data/huggingface/hub/models--mlx-community--Breeze-TTS-2-mlx/snapshots/3c8829fb7fd335818f085cd2ef49b4100c0e46c8'
    required = ['model-00001-of-00002.safetensors', 'model-00002-of-00002.safetensors', 'audio_tokenizer/model.safetensors']
    if not all((model/name).is_file() for name in required):
        print('模型下载尚未完成，请等待安装结束'); sys.exit(1)
    if active():
        print('服务已启动'); sys.exit(0)
    (root/'logs').mkdir(exist_ok=True)
    (root/'data').mkdir(exist_ok=True)
    with open(root/'logs/service.log', 'ab') as log:
        process = subprocess.Popen(['/bin/bash', str(root/'start.sh')], stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
    pidfile.write_text(str(process.pid))
    print('服务正在加载模型，请稍候')
elif sys.argv[1] == 'stop':
    pid = active()
    if pid: os.kill(pid, signal.SIGTERM)
    pidfile.unlink(missing_ok=True)
    print('服务已停止')
else:
    print('运行中' if active() else '未运行')
