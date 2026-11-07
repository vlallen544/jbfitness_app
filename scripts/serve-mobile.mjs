import { createServer } from "node:http";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { resolve, sep, extname } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(
  new URL(process.argv.includes('--client-preview')
    ? "../apps/mobile/build/client-preview-web/"
    : "../apps/mobile/build/web/", import.meta.url),
);
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".json": "application/json",
  ".wasm": "application/wasm",
  ".css": "text/css",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
};
try {
  await stat(resolve(root, "index.html"));
} catch {
  console.error(
    "Build the preview first: bash scripts/mobile.sh build web --no-web-resources-cdn",
  );
  process.exit(1);
}
createServer(async (request, response) => {
  try {
    if (!["GET", "HEAD"].includes(request.method ?? "")) {
      response.writeHead(405).end();
      return;
    }
    const pathname = decodeURIComponent(
      new URL(request.url ?? "/", "http://localhost").pathname,
    );
    let path = resolve(root, `.${pathname}`);
    if (path !== resolve(root) && !path.startsWith(resolve(root) + sep)) {
      response.writeHead(403).end();
      return;
    }
    let info = await stat(path);
    if (info.isDirectory()) {
      path = resolve(path, "index.html");
      info = await stat(path);
    }
    response.writeHead(200, {
      "Content-Type": types[extname(path)] ?? "application/octet-stream",
      "Content-Length": info.size,
      "Cache-Control": "no-store",
    });
    if (request.method === "HEAD") response.end();
    else
      createReadStream(path)
        .on("error", () => response.destroy())
        .pipe(response);
  } catch {
    response.writeHead(404).end("Not found");
  }
}).listen(8080, "127.0.0.1", () =>
  console.log("JB Fitness mobile preview: http://localhost:8080"),
);
