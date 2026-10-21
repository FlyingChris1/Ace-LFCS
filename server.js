const http = require('http');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const pty = require('node-pty');
const { WebSocketServer, WebSocket } = require('ws');

const PORT = 8765;
const MP = 'C:\\Program Files\\Multipass\\bin\\multipass.exe';
const root = __dirname;
const tasks = JSON.parse(fs.readFileSync(path.join(root, 'tasks.json'), 'utf8'));
const hosts = ['terminal', 'data-001', 'data-002', 'app-srv1', 'web-srv1'];
const labs = new Map();
let currentTask = null;
let currentHost = null;

function run(args, timeout = 900000) {
  return new Promise(resolve => {
    const child = spawn(MP, args, { windowsHide: true });
    let out = '';
    let done = false;
    const timer = setTimeout(() => {
      child.kill();
      finish(124, out + '\nMultipass operation timed out.');
    }, timeout);
    function finish(code, result) {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve({ code, out: result });
    }
    child.stdout.on('data', chunk => { out += chunk; });
    child.stderr.on('data', chunk => { out += chunk; });
    child.on('error', error => finish(1, out + String(error)));
    child.on('close', code => finish(code ?? 1, out));
  });
}

async function runWithRetry(args, timeout = 900000, attempts = 3) {
  let result;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    result = await run(args, timeout);
    if (result.code === 0 || !/ssh connection failed|Timeout connecting to/i.test(result.out) || attempt === attempts) return result;
    await new Promise(resolve => setTimeout(resolve, 1500 * attempt));
  }
  return result;
}

const slug = value => String(value).toLowerCase().replace(/[^a-z0-9-]/g, '-');
const baseName = host => host === 'terminal' ? 'lfcs-terminal' : host;
const labKey = (task, host) => `${task}:${host}`;
const labName = (task, host) => `lfcs-q${task}-${slug(host)}`;
const taskById = id => tasks.find(task => task.id === String(id));

const browserAssets = {
  '/vendor/xterm.js': ['node_modules/@xterm/xterm/lib/xterm.js', 'text/javascript; charset=utf-8'],
  '/vendor/xterm.css': ['node_modules/@xterm/xterm/css/xterm.css', 'text/css; charset=utf-8'],
  '/vendor/addon-fit.js': ['node_modules/@xterm/addon-fit/lib/addon-fit.js', 'text/javascript; charset=utf-8']
};

async function makeLab(taskId, host, reset = false) {
  const task = taskById(taskId);
  if (!task || !hosts.includes(host)) throw new Error('Unknown exercise or host.');
  const name = labName(taskId, host);
  const base = baseName(host);
  const baseInfo = await run(['info', base], 30000);
  if (baseInfo.code !== 0) throw new Error(`Base VM ${base} is missing. Run prepare-vms.ps1 first.`);
  if (reset) {
    await run(['stop', name], 30000);
    await run(['delete', '--purge', name], 120000);
    labs.delete(labKey(taskId, host));
  }
  let instanceInfo = await run(['info', name], 30000);
  if (instanceInfo.code !== 0) {
    const state = (baseInfo.out.match(/State:\s+(\w+)/) || [])[1];
    if (state === 'Running') {
      const stopBase = await run(['stop', base], 60000);
      if (stopBase.code !== 0) throw new Error(`Could not stop clean base VM ${base}: ${stopBase.out}`);
    }
    const clone = await run(['clone', base, '--name', name], 120000);
    if (clone.code !== 0) throw new Error(clone.out || `Could not clone ${base}.`);
    const start = await run(['start', name], 240000);
    if (start.code !== 0) throw new Error(start.out || `Could not start ${name}.`);
    const transfer = await run(['transfer', path.join(root, 'provision.sh'), `${name}:/tmp/lfcs-provision.sh`]);
    if (transfer.code !== 0) throw new Error(transfer.out);
    const provision = await run(['exec', name, '--', 'sudo', 'bash', '-lc', `sed -i 's/\r$//' /tmp/lfcs-provision.sh && bash /tmp/lfcs-provision.sh ${taskId} ${host}`], 900000);
    if (provision.code !== 0) throw new Error(provision.out || `Provisioning ${name} failed.`);
    instanceInfo = await run(['info', name], 30000);
  } else {
    const state = (instanceInfo.out.match(/State:\s+(\w+)/) || [])[1];
    if (state !== 'Running') {
      const start = await run(['start', name], 240000);
      if (start.code !== 0) throw new Error(start.out || `Could not start ${name}.`);
    }
  }
  const record = labs.get(labKey(taskId, host)) || { name, cwd: '/home/candidate' };
  labs.set(labKey(taskId, host), record);
  return record;
}

async function ensureTaskCompanions(taskId) {
  const extras = taskId === '10' ? ['terminal', 'app-srv1']
    : taskId === '7' ? ['data-001', 'data-002', 'app-srv1'] : [];
  for (const host of extras) await makeLab(taskId, host, false);
}

async function pauseOtherExercises(taskId) {
  for (const [key, record] of labs.entries()) {
    const otherTask = key.split(':', 1)[0];
    if (otherTask !== taskId) await run(['stop', record.name], 30000);
  }
}

const html = `<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>LFCS Local Lab</title>
<link rel="stylesheet" href="/vendor/xterm.css"><style>
*{box-sizing:border-box}body{margin:0;background:#111821;color:#e8eef4;font:15px system-ui}header{padding:14px 22px;background:#1b2733;display:flex;justify-content:space-between}main{height:calc(100vh - 54px);display:grid;grid-template-columns:minmax(360px,42%) 1fr}.left{padding:20px;overflow:auto;border-right:1px solid #354353}.right{padding:12px;display:flex;flex-direction:column;min-width:0;min-height:0}select,button{background:#253342;color:#fff;border:1px solid #4b5c6e;border-radius:5px;padding:9px}label{margin-right:10px}button{cursor:pointer}button:disabled{opacity:.5;cursor:wait}.row{display:flex;gap:8px;margin:14px 0}#prompt{white-space:pre-wrap;line-height:1.5}small{color:#acbac7}#terminal{flex:1;min-height:0;overflow:hidden;background:#070a0d;padding:8px;border:1px solid #354353;border-radius:5px}#terminal .xterm{height:100%}#status{color:#8fc9ff}.badge{color:#97a9b8;font-size:13px}@media(max-width:850px){main{height:auto;min-height:calc(100vh - 54px);grid-template-columns:1fr}.left{border-right:0;border-bottom:1px solid #354353}.right{height:60vh}}
</style></head><body><header><b>LFCS Local Lab</b><span id="status">Bereit</span></header>
<main><section class="left"><label>Aufgabe <select id="task"></select></label>
<div class="row"><button id="start">Start / zurücksetzen</button><button id="check">Lösung prüfen</button></div><div class="badge" id="vmstate">Umgebung nicht gestartet</div><div class="badge">Aufgabenserver: <strong id="targetServer"></strong></div><h2 id="title"></h2><p id="prompt"></p><small>Linux-Terminal als candidate mit sudo-Rechten. Mit <code>ssh servername</code> wechselst du zu einem anderen Aufgabenserver. Pfeiltasten, Tab-Vervollständigung, Ctrl+C, Shell-Verlauf sowie interaktive Programme wie vim und nano werden unterstützt.</small></section>
<section class="right"><div id="terminal"></div></section></main>
<script src="/vendor/xterm.js"></script><script src="/vendor/addon-fit.js"></script>
<script>
const tasks=${JSON.stringify(tasks)};const s=document.querySelector('#task'),st=document.querySelector('#status'),vmst=document.querySelector('#vmstate'),targetServer=document.querySelector('#targetServer');let active=false,busy=false,socket=null;
const term=new Terminal({cursorBlink:true,scrollback:10000,fontSize:14,fontFamily:'Cascadia Mono, Consolas, monospace',theme:{background:'#070a0d',foreground:'#e8eef4',cursor:'#f2f6fa',selectionBackground:'#39536f'}});const fitAddon=new FitAddon.FitAddon();term.loadAddon(fitAddon);term.open(document.querySelector('#terminal'));fitAddon.fit();
function closeTerminal(){if(socket){socket.close();socket=null}}
function terminalMessage(message){closeTerminal();term.reset();term.writeln(message);fitAddon.fit()}
function attachTerminal(task,host){closeTerminal();term.reset();term.writeln('Opening Linux shell…');const scheme=location.protocol==='https:'?'wss':'ws';const ws=new WebSocket(scheme+'://'+location.host+'/terminal?task='+encodeURIComponent(task)+'&host='+encodeURIComponent(host));socket=ws;ws.onopen=()=>{if(socket!==ws)return;term.reset();fitAddon.fit();ws.send(JSON.stringify({type:'resize',cols:term.cols,rows:term.rows}));term.focus()};ws.onmessage=e=>{if(socket!==ws)return;try{const m=JSON.parse(e.data);if(m.type==='output')term.write(m.data);else if(m.type==='exit')term.writeln('\\r\\n[Shell exited]')}catch{}};ws.onerror=()=>{if(socket===ws)terminalMessage('Could not connect to the VM terminal. Start or reconnect the exercise.')}}
term.onData(data=>{if(socket&&socket.readyState===WebSocket.OPEN)socket.send(JSON.stringify({type:'input',data}))});const fitObserver=new ResizeObserver(()=>{fitAddon.fit();if(socket&&socket.readyState===WebSocket.OPEN)socket.send(JSON.stringify({type:'resize',cols:term.cols,rows:term.rows}))});fitObserver.observe(document.querySelector('#terminal'));
tasks.forEach(t=>{const o=document.createElement('option');o.value=t.id;o.textContent=t.id+'. '+t.name;s.append(o)});
function hostForTask(){return selected().host}
function setBusy(value){busy=value;document.querySelector('#start').disabled=value;document.querySelector('#check').disabled=value;st.textContent=value?'VM wird vorbereitet…':'Bereit'}
function selected(){return tasks.find(t=>t.id===s.value)}
async function post(url,data){const response=await fetch(url,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(data)});return response.json()}
async function connect(){active=false;closeTerminal();const t=selected(),host=hostForTask();targetServer.textContent=host;document.querySelector('#title').textContent='Question '+t.id+' | '+t.name;document.querySelector('#prompt').textContent=t.prompt;vmst.textContent='Umgebung nicht gestartet';terminalMessage('Aufgabe '+t.id+' · VM '+host+'\\nStarte die Umgebung, um loszulegen.');try{const r=await post('/connect',{task:t.id,host});if(r.ok){active=true;vmst.textContent='Verbunden mit '+r.name;attachTerminal(t.id,host)}}catch{}}
s.onchange=connect;connect();
document.querySelector('#start').onclick=async()=>{const host=hostForTask();setBusy(true);active=false;closeTerminal();terminalMessage('VM wird gestartet, Pakete und Ausgangslage werden vorbereitet…');try{const r=await post('/start',{task:s.value,host});if(!r.ok)throw new Error(r.error||r.out);active=true;vmst.textContent='Verbunden mit '+r.name;attachTerminal(s.value,host)}catch(e){st.textContent='Fehler';terminalMessage(String(e));vmst.textContent='VM-Start fehlgeschlagen'}finally{setBusy(false)}};
document.querySelector('#check').onclick=async()=>{if(!active){st.textContent='Starte zuerst die Umgebung';return}setBusy(true);try{const r=await post('/check',{task:s.value,host:hostForTask()});st.textContent=r.ok?'Richtig':'Noch falsch';term.writeln('');term.writeln('[Prüfung] '+(r.ok?'RICHTIG':'NOCH FALSCH')+' — '+r.message);term.focus()}catch(e){st.textContent='Prüffehler';term.writeln(String(e))}finally{setBusy(false)}};</script></body></html>`;

function json(res, data) { res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(data)); }
async function body(req) { let text=''; for await (const chunk of req) text+=chunk; return JSON.parse(text || '{}'); }

async function handler(req, res) {
  if (req.method === 'GET' && browserAssets[req.url]) {
    const [relativePath, contentType] = browserAssets[req.url];
    const file = path.join(root, relativePath);
    if (!fs.existsSync(file)) { res.writeHead(500); return res.end('Run npm install in the project folder.'); }
    res.writeHead(200, { 'content-type': contentType, 'cache-control': 'public, max-age=3600' });
    return res.end(fs.readFileSync(file));
  }
  if (req.method === 'GET' && req.url === '/') { res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); return res.end(html); }
  if (req.method !== 'POST') { res.writeHead(404); return res.end(); }
  let data;
  try { data = await body(req); } catch { return json(res, { error: 'Invalid request body.' }); }
  const task = taskById(data.task);
  const host = data.host;
  if (!task || !hosts.includes(host)) return json(res, { error: 'Unknown task or VM.' });

  if (req.url === '/connect') {
    let record = labs.get(labKey(task.id, host));
    if (!record) {
      const info = await run(['info', labName(task.id, host)], 30000);
      if (info.code !== 0) return json(res, { ok: false });
      record = { name: labName(task.id, host), cwd: '/home/candidate' };
      labs.set(labKey(task.id, host), record);
    }
    await pauseOtherExercises(task.id);
    const info = await run(['info', record.name], 30000);
    if (info.code !== 0) return json(res, { ok: false });
    if (!/State:\s+Running/.test(info.out)) {
      const start = await run(['start', record.name], 240000);
      if (start.code !== 0) return json(res, { ok: false });
    }
    currentTask = task.id; currentHost = host;
    return json(res, { ok: true, name: record.name });
  }

  if (req.url === '/start') {
    try {
      await pauseOtherExercises(task.id);
      let prepared = [];
      if (task.id === '10') prepared = ['app-srv1','terminal'];
      if (task.id === '7') prepared = ['data-001','app-srv1','data-002'];
      for (const target of prepared) await makeLab(task.id, target, true);
        let record = prepared.includes(host) ? labs.get(labKey(task.id, host)) : await makeLab(task.id, host, true);
      currentTask = task.id; currentHost = host;
      return json(res, { ok: true, name: record.name, out: `VM ${record.name} ist für Aufgabe ${task.id} vorbereitet.\n` });
    } catch (error) { return json(res, { ok: false, error: String(error.message || error) }); }
  }

  if (req.url === '/run') {
    if (currentTask !== task.id || currentHost !== host) return json(res, { error: 'VM zuerst auswählen und starten.' });
    const record = labs.get(labKey(task.id, host));
    if (!record) return json(res, { error: 'VM zuerst starten.' });
    const command = String(data.command || '');
    if (command.length > 20000) return json(res, { error: 'Command too long.' });
    const cwd = record.cwd.startsWith('/') ? record.cwd : '/home/candidate';
    const wrapped = `cd ${JSON.stringify(cwd)} 2>/dev/null || cd /home/candidate\n${command}\n__lab_rc=$?\nprintf '\\n__LAB_CWD__%s\\n' "$PWD"\nexit $__lab_rc`;
    const result = await runWithRetry(['exec', record.name, '--', 'sudo', '-u', 'candidate', '-H', 'bash', '-lc', wrapped], 300000);
    const marker = result.out.match(/\n__LAB_CWD__(.*?)\r?\n?$/);
    if (marker) { record.cwd = marker[1]; result.out = result.out.slice(0, marker.index); }
    return json(res, { out: result.out || (result.code === 0 ? '' : `Command exited with ${result.code}.`) });
  }

  if (req.url === '/check') {
    if (currentTask !== task.id || currentHost !== host) return json(res, { ok: false, message: 'Starte zuerst diese VM.' });
    const targets = task.id === '10' ? ['terminal','app-srv1']
      : task.id === '7' ? ['data-002','data-001','app-srv1'] : [host];
    const results = [];
    for (const target of targets) {
      const record = labs.get(labKey(task.id, target));
      if (!record) return json(res, { ok: false, message: `Die VM ${target} wurde noch nicht gestartet.` });
      const transfer = await runWithRetry(['transfer', path.join(root, 'grade.sh'), `${record.name}:/tmp/lfcs-grade.sh`]);
      if (transfer.code !== 0) return json(res, { ok: false, message: transfer.out });
      const grade = await runWithRetry(['exec', record.name, '--', 'sudo', 'bash', '-lc', `sed -i 's/\r$//' /tmp/lfcs-grade.sh && bash /tmp/lfcs-grade.sh ${task.id}`], 60000);
      const lastLine = grade.out.trim().split('\n').pop() || '';
      const bits = lastLine.split('|');
      results.push({ ok: bits[0] === 'PASS', message: bits.slice(1).join('|') || grade.out || `grader exit ${grade.code}` });
    }
    const failed = results.find(result => !result.ok);
    return json(res, { ok: !failed, message: failed ? failed.message : results.map(result => result.message).join(' ') });
  }

  res.writeHead(404); res.end();
}

const server = http.createServer((req, res) => handler(req, res).catch(error => json(res, { error: String(error) })));
const wss = new WebSocketServer({ noServer: true, maxPayload: 1024 * 1024 });

function openInteractiveShell(ws, record) {
  let shell;
  try {
    shell = pty.spawn(MP, ['exec', record.name, '--', 'sudo', '-iu', 'candidate'], {
      name: 'xterm-256color', cols: 100, rows: 30, cwd: root,
      env: { ...process.env, TERM: 'xterm-256color', COLORTERM: 'truecolor' }
    });
  } catch (error) {
    ws.send(JSON.stringify({ type: 'output', data: `Could not start the Linux PTY: ${error.message}\r\n` }));
    ws.close(1011, 'PTY start failed');
    return;
  }
  shell.onData(data => { if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'output', data })); });
  shell.onExit(({ exitCode }) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'exit', exitCode }));
      ws.close(1000, 'Shell exited');
    }
  });
  ws.on('message', raw => {
    let message;
    try { message = JSON.parse(raw.toString()); } catch { return; }
    if (message.type === 'input' && typeof message.data === 'string' && message.data.length <= 65536) shell.write(message.data);
    if (message.type === 'resize') {
      const cols = Math.max(20, Math.min(400, Number(message.cols) || 80));
      const rows = Math.max(5, Math.min(160, Number(message.rows) || 24));
      shell.resize(cols, rows);
    }
  });
  ws.on('close', () => { try { shell.kill(); } catch {} });
  ws.on('error', () => { try { shell.kill(); } catch {} });
}

server.on('upgrade', (request, socket, head) => {
  let url;
  try { url = new URL(request.url, 'http://localhost'); } catch { socket.destroy(); return; }
  if (url.pathname !== '/terminal') { socket.destroy(); return; }
  const task = taskById(url.searchParams.get('task'));
  const host = url.searchParams.get('host');
  const record = task && hosts.includes(host) ? labs.get(labKey(task.id, host)) : null;
  if (!record || currentTask !== task.id || currentHost !== host) { socket.write('HTTP/1.1 403 Forbidden\r\n\r\n'); socket.destroy(); return; }
  wss.handleUpgrade(request, socket, head, ws => wss.emit('connection', ws, request, record));
});
wss.on('connection', (ws, _request, record) => openInteractiveShell(ws, record));
server.listen(PORT, '127.0.0.1', () => console.log(`LFCS Local Lab: http://localhost:${PORT}`));
