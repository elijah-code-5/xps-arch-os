const { app, BrowserWindow, Menu, ipcMain } = require('electron');
const path = require('path');
const { Client } = require('ssh2');

// AppImages often can't use Chromium's SUID sandbox, so run without it.
app.commandLine.appendSwitch('no-sandbox');

function createWindow() {
  const win = new BrowserWindow({
    width: 1360,
    height: 900,
    minWidth: 900,
    minHeight: 640,
    title: 'EV3 Bench',
    backgroundColor: '#0055BF',
    autoHideMenuBar: true,
    icon: path.join(__dirname, 'icon.png'),
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, 'preload.js')
    }
  });
  Menu.setApplicationMenu(null);
  win.loadFile(path.join(__dirname, 'index.html'));
}

/* ---------- real EV3 (ev3dev) over SSH ---------- */
let conn = null;

function send(text, err) {
  BrowserWindow.getAllWindows().forEach((w) =>
    w.webContents.send('ev3-out', { text: String(text), err: !!err })
  );
}

ipcMain.handle('ev3-stop', () =>
  new Promise((resolve) => {
    if (!conn) return resolve();
    const c = conn;
    conn = null;
    c.exec("pkill -f '[e]v3bench.py'", () => {
      c.end();
      resolve();
    });
  })
);

ipcMain.handle('ev3-run', (_e, o) =>
  new Promise((resolve, reject) => {
    if (conn) {
      try { conn.end(); } catch (_) {}
      conn = null;
    }
    const c = new Client();
    conn = c;
    const file = '/home/' + o.user + '/ev3bench.py';
    c.on('ready', () => {
      send('Connected. Sending program...');
      c.sftp((err, sftp) => {
        if (err) return reject(err);
        const ws = sftp.createWriteStream(file, { mode: 0o755 });
        ws.on('error', reject);
        ws.on('close', () => {
          c.exec('python3 -u ' + file, (err2, stream) => {
            if (err2) return reject(err2);
            send('Running on the brick.');
            stream.on('data', (d) => send(d.toString()));
            stream.stderr.on('data', (d) => send(d.toString(), true));
            stream.on('close', (code) => {
              send('Program ended (exit ' + code + ')');
              c.end();
              if (conn === c) conn = null;
              resolve(code);
            });
          });
        });
        ws.end(String(o.code || '').replace(/\r\n/g, '\n'));
      });
    });
    c.on('error', (err) => {
      if (conn === c) conn = null;
      reject(err);
    });
    c.connect({
      host: o.host,
      port: 22,
      username: o.user,
      password: o.password,
      readyTimeout: 15000
    });
  })
);

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => app.quit());
