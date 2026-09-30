import { WASI, File, OpenFile, ConsoleStdout } from './node_modules/@bjorn3/browser_wasi_shim/dist/index.js';

// The browser executes the real Swift executable in a Worker. This probe has
// one request and one world lifetime; it does not implement the W1 command bridge.
self.onmessage = async () => {
  let stdout = '';
  let stderr = '';
  try {
    const response = await fetch('./.artifacts/probe.wasm');
    if (!response.ok) throw new Error(`Wasm fetch failed: ${response.status}`);
    const wasi = new WASI(['RailwayWasmProbe'], [], [
      new OpenFile(new File(new Uint8Array())),
      ConsoleStdout.lineBuffered(line => { stdout += `${line}\n`; }),
      ConsoleStdout.lineBuffered(line => { stderr += `${line}\n`; }),
    ]);
    const { instance } = await WebAssembly.instantiateStreaming(response, { wasi_snapshot_preview1: wasi.wasiImport });
    const exitCode = wasi.start(instance);
    if (exitCode !== 0) throw new Error(`WASI exit ${exitCode}: ${stderr}`);
    self.postMessage({ ok: true, report: JSON.parse(stdout), stderr });
  } catch (error) {
    self.postMessage({ ok: false, error: String(error), stdout, stderr });
  }
};
