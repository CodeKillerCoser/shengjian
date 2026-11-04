from pathlib import Path
import json, tempfile, subprocess, threading, wave, os

os.chdir(Path(__file__).resolve().parents[1])
qa_directory = tempfile.TemporaryDirectory(prefix="shengjian-checks-")
from http.server import HTTPServer, BaseHTTPRequestHandler
root=Path(qa_directory.name)
for filename in ['sample.wav', 'core.wav']:
    with wave.open(str(root/filename),'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(16000); f.writeframes(bytes(64000))
(root/'test-ggml.bin').write_bytes(b'test')
fake=root/'fake-whisper.py'
fake.write_text('#!/usr/bin/env python3\nimport sys\nfrom pathlib import Path\nPath(sys.argv[sys.argv.index("-of")+1]+".txt").write_text("这是转写测试。")\n')
fake.chmod(0o755)
slow=root/'slow-whisper.py'
slow.write_text('#!/usr/bin/env python3\nimport sys, os, time\nfrom pathlib import Path\nPath(sys.argv[sys.argv.index("-of")+1]+".pid").write_text(str(os.getpid()))\ntime.sleep(60)\n')
slow.chmod(0o755)
class Handler(BaseHTTPRequestHandler):
    def authorized(self):
        if self.path.startswith('/auth/') and self.headers.get('Authorization') != 'Bearer saved-key':
            self.send_response(401); self.end_headers(); return False
        return True
    def do_GET(self):
        if not self.authorized(): return
        if self.path=='/health':
            self.send_response(200); self.end_headers(); self.wfile.write(b'{}'); return
        assert self.path=='/auth/v1/models'
        self.send_response(200); self.end_headers()
        self.wfile.write(b'{"data":[{"id":"z"},{"id":"a"},{"id":"z"}]}')
    def do_POST(self):
        if not self.authorized(): return
        if self.path=='/v1/audio/speech':
            body=self.rfile.read(int(self.headers['Content-Length']))
            assert b'multipart/form-data' in self.headers['Content-Type'].encode()
            assert b'name="text"' in body and '合成测试'.encode() in body
            assert b'name="instruction"' in body
            self.send_response(200); self.end_headers(); self.wfile.write(bytes(4800)); return
        assert self.path in ['/v1/chat/completions', '/auth/v1/chat/completions']
        data=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if data['model']=='server-error': self.send_response(500); self.end_headers(); return
        response={'model':'actual-test-model','choices':[{'message':{'content':'这是整理结果。'}}]}
        if data['model']!='no-usage': response['usage']={'prompt_tokens':12,'completion_tokens':8,'total_tokens':20}
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(json.dumps(response).encode())
    def log_message(self,*a): pass
server=HTTPServer(('127.0.0.1',0), Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
frameworks=['SwiftUI','AppKit','AVFoundation','Speech','Security','Carbon']
sources=[str(p) for p in sorted(Path('Sources').rglob('*.swift')) if 'App' not in p.parts]
core_sources=[p for p in sources if 'Presentation' not in Path(p).parts]
core_cmd=['swiftc','-parse-as-library','-swift-version','5']+core_sources+['Tests/CoreChecks.swift','Tests/BreezeChecks.swift','-o',str(root/'core-checks')]
for name in frameworks:
    if name != 'SwiftUI': core_cmd+=['-framework',name]
subprocess.run(core_cmd,check=True)
subprocess.run([str(root/'core-checks'),str(root.resolve()),str(server.server_port)],check=True)
cmd=['swiftc','-parse-as-library','-swift-version','5']+sources+['Tests/HistoryChecks.swift','Tests/PermissionChecks.swift','-o',str(root/'checks')]
for name in frameworks: cmd+=['-framework',name]
subprocess.run(cmd,check=True)
subprocess.run([str(root/'checks'),str(root.resolve()),str(server.server_port)],check=True)
print('Isolated QA data:',root/'data')
server.shutdown()
