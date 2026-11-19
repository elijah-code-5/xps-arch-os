const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('ev3bench', {
  run: (opts) => ipcRenderer.invoke('ev3-run', opts),
  stop: () => ipcRenderer.invoke('ev3-stop'),
  onOutput: (cb) => ipcRenderer.on('ev3-out', (_e, d) => cb(d))
});
