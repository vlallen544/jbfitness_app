import { writeFile } from "node:fs/promises";

// Local development QA only. Start a dedicated Chromium on port 9234.
export async function browserSession() {
  const tabs = await (await fetch("http://127.0.0.1:9234/json/list")).json();
  const page = tabs.find((tab) => tab.type === "page");
  if (!page) throw new Error("Open a page in the dedicated QA browser.");
  const socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.onopen = resolve;
    socket.onerror = reject;
  });
  let sequence = 0;
  const pending = new Map();
  const eventHandlers = new Set();
  socket.onmessage = ({ data }) => {
    const message = JSON.parse(data);
    if (message.method) {
      for (const handler of eventHandlers) handler(message);
    }
    const task = pending.get(message.id);
    if (task) {
      pending.delete(message.id);
      clearTimeout(task.timeout);
      message.error
        ? task.reject(new Error(message.error.message))
        : task.resolve(message.result);
    }
  };
  const call = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++sequence;
      const timeout = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`Browser command timed out: ${method}`));
      }, 15000);
      pending.set(id, { resolve, reject, timeout });
      socket.send(JSON.stringify({ id, method, params }));
    });
  const evaluate = async (expression) => {
    const result = await call("Runtime.evaluate", {
      expression,
      returnByValue: true,
      awaitPromise: true,
    });
    if (result.exceptionDetails) throw new Error("Browser evaluation failed.");
    return result.result.value;
  };
  const screenshot = async (path) => {
    const result = await call("Page.captureScreenshot", {
      format: "png",
      fromSurface: true,
    });
    await writeFile(path, Buffer.from(result.data, "base64"));
  };
  await call("Page.enable");
  await call("Emulation.setDeviceMetricsOverride", {
    width: 390,
    height: 844,
    deviceScaleFactor: 1,
    mobile: true,
  });
  return { call, evaluate, screenshot, onEvent: (handler) => eventHandlers.add(handler), close: () => socket.close() };
}
