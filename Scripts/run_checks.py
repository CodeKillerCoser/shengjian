from pathlib import Path
import json, tempfile, subprocess, threading, wave, os

os.chdir(Path(__file__).resolve().parents[1])
qa_directory = tempfile.TemporaryDirectory(prefix="shengjian-checks-")
from http.server import HTTPServer, BaseHTTPRequestHandler
root=Path(qa_directory.name)
with wave.open(str(root/'sample.wav'),'wb') as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(16000); f.writeframes(bytes(64000))
(root/'test-ggml.bin').write_bytes(b'test')
fake=root/'fake-whisper.py'
fake.write_text('#!/usr/bin/env python3\nimport sys\nfrom pathlib import Path\nPath(sys.argv[sys.argv.index("-of")+1]+".txt").write_text("这是转写测试。")\n')
fake.chmod(0o755)
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        assert self.path=='/v1/chat/completions'
        data=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if data['model']=='server-error': self.send_response(500); self.end_headers(); return
        response={'model':'actual-test-model','choices':[{'message':{'content':'这是整理结果。'}}]}
        if data['model']!='no-usage': response['usage']={'prompt_tokens':12,'completion_tokens':8,'total_tokens':20}
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(json.dumps(response).encode())
    def log_message(self,*a): pass
server=HTTPServer(('127.0.0.1',0), Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
source=Path('Sources/main.swift').read_text().replace('@main struct RimeVoiceApp:', 'struct RimeVoiceApp:')
(root/'AppUnderTest.swift').write_text(source)
frameworks=['SwiftUI','AppKit','AVFoundation','Speech','Security','Carbon']
cmd=['swiftc','-parse-as-library','-swift-version','5',str(root/'AppUnderTest.swift')]+[str(p) for p in sorted(Path('Sources').glob('*.swift')) if p.name!='main.swift']+['Tests/HistoryChecks.swift','Tests/PermissionChecks.swift','-o',str(root/'checks')]
for name in frameworks: cmd+=['-framework',name]
subprocess.run(cmd,check=True)
subprocess.run([str(root/'checks'),str(root.resolve()),str(server.server_port)],check=True)
print('Isolated QA data:',root/'data')
server.shutdown()
