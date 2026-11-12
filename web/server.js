// Tiny static dev server for the avatar page. Loopback only, no dependencies.
import http from "node:http";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.PORT || process.argv[2] || 8080);

const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json",
  ".glb": "model/gltf-binary",
  ".bin": "application/octet-stream",
  ".wasm": "application/wasm",
  ".css": "text/css; charset=utf-8",
};

// Only these top-level entries are served (keeps package.json etc. private).
const allowed = ["index.html", "pcm-player.js", "avatars", "node_modules", "renderers", "vendor"];

http.createServer(async (req, res) => {
  try {
    let rel = decodeURIComponent(new URL(req.url, "http://x").pathname);
    if (rel === "/") rel = "/index.html";
    const file = path.normalize(path.join(root, rel));
    if (!file.startsWith(root + path.sep) || !allowed.includes(path.relative(root, file).split(path.sep)[0])) {
      res.writeHead(404).end("not found");
      return;
    }
    if (!(await stat(file)).isFile()) throw new Error("not a file");
    const body = await readFile(file);
    res.writeHead(200, {
      "Content-Type": types[path.extname(file)] || "application/octet-stream",
      "Cache-Control": "no-cache",
    });
    res.end(body);
  } catch {
    res.writeHead(404).end("not found");
  }
}).listen(port, "127.0.0.1", () => {
  console.log(`avatar page: http://127.0.0.1:${port}/`);
});
