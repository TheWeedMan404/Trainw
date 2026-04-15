const http = require("http");
const fs = require("fs");
const path = require("path");

const root = __dirname;
const preferredPort = Number(process.env.PORT || 3000);

const mimeTypes = {
  ".css": "text/css; charset=utf-8",
  ".gif": "image/gif",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".jpeg": "image/jpeg",
  ".jpg": "image/jpeg",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8",
  ".webp": "image/webp"
};

const rewriteMap = new Map([
  ["/role", "/tw-role.html"],
  ["/login", "/tw-login.html"],
  ["/admin", "/tw-gym-acc.html"],
  ["/dashboard", "/tw-gym-acc.html"],
  ["/dashboard/gym", "/tw-gym-acc.html"],
  ["/dashboard/coach", "/tw-coach-acc.html"],
  ["/dashboard/client", "/tw-client-acc.html"],
  ["/coach", "/tw-coach-acc.html"],
  ["/client", "/tw-client-acc.html"],
  ["/gate", "/gate-terminal.html"],
]);

function readFileIfExists(filePath) {
  try {
    return fs.readFileSync(filePath, "utf8");
  } catch (_error) {
    return null;
  }
}

function discoverSupabaseConfig() {
  const envUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || "";
  const envKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY || "";

  if (envUrl && envKey) {
    return { url: envUrl, key: envKey, source: "environment" };
  }

  const candidateFiles = [
    path.join(root, "tw-coach-acc.html"),
    path.join(root, "dist", "tw-coach-acc.html"),
    path.join(root, "tw-login.html"),
    path.join(root, "tw-role.html"),
  ];

  for (const candidate of candidateFiles) {
    const text = readFileIfExists(candidate);
    if (!text) continue;

    const urlMatch = text.match(/window\.__TRAINW_URL__\s*=\s*['"]([^'"]+)['"]/);
    const keyMatch = text.match(/window\.__TRAINW_KEY__\s*=\s*['"]([^'"]+)['"]/);

    if (!urlMatch || !keyMatch) continue;
    if (/%%SUPABASE_/i.test(urlMatch[1]) || /%%SUPABASE_/i.test(keyMatch[1])) continue;

    return { url: urlMatch[1], key: keyMatch[1], source: path.basename(candidate) };
  }

  return { url: "", key: "", source: "missing" };
}

const runtimeSupabaseConfig = discoverSupabaseConfig();

function replaceConfigPlaceholders(htmlSource) {
  if (!htmlSource.includes("%%SUPABASE_URL%%") && !htmlSource.includes("%%SUPABASE_ANON_KEY%%")) {
    return htmlSource;
  }

  if (!runtimeSupabaseConfig.url || !runtimeSupabaseConfig.key) {
    return htmlSource;
  }

  return htmlSource
    .replace(/'%%SUPABASE_URL%%'/g, JSON.stringify(runtimeSupabaseConfig.url))
    .replace(/'%%SUPABASE_ANON_KEY%%'/g, JSON.stringify(runtimeSupabaseConfig.key))
    .replace(/%%SUPABASE_URL%%/g, runtimeSupabaseConfig.url)
    .replace(/%%SUPABASE_ANON_KEY%%/g, runtimeSupabaseConfig.key);
}

function send(res, status, body, headers = {}) {
  res.writeHead(status, headers);
  res.end(body);
}

function safeResolve(requestPath) {
  const rawPath = decodeURIComponent((requestPath || "/").split("?")[0]);
  const rewrittenPath = rewriteMap.get(rawPath) || rawPath;
  const normalized = rewrittenPath.replace(/^\/+/, "");
  const candidates = [];

  if (!normalized) {
    candidates.push(path.join(root, "index.html"));
  } else {
    candidates.push(path.join(root, normalized));
    if (!path.extname(normalized)) {
      candidates.push(path.join(root, `${normalized}.html`));
      candidates.push(path.join(root, normalized, "index.html"));
    }
  }

  for (const candidate of candidates) {
    const resolved = path.resolve(candidate);
    if (!resolved.startsWith(root)) continue;

    if (fs.existsSync(resolved)) {
      const stats = fs.statSync(resolved);
      if (stats.isDirectory()) {
        const indexFile = path.join(resolved, "index.html");
        if (fs.existsSync(indexFile)) return indexFile;
        continue;
      }
      return resolved;
    }
  }

  return null;
}

function handleRequest(req, res) {
  const method = req.method || "GET";

  if (!["GET", "HEAD"].includes(method)) {
    send(res, 405, "Method Not Allowed", { "Content-Type": "text/plain; charset=utf-8" });
    return;
  }

  const filePath = safeResolve(req.url || "/");

  if (!filePath) {
    send(res, 404, "Not Found", { "Content-Type": "text/plain; charset=utf-8" });
    return;
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = mimeTypes[ext] || "application/octet-stream";

  fs.readFile(filePath, (error, data) => {
    if (error) {
      send(res, 500, "Internal Server Error", { "Content-Type": "text/plain; charset=utf-8" });
      return;
    }

    res.writeHead(200, {
      "Cache-Control": "no-store",
      "Content-Type": contentType
    });

    if (method === "HEAD") {
      res.end();
      return;
    }

    if (ext === ".html") {
      const html = replaceConfigPlaceholders(data.toString("utf8"));
      res.end(html, "utf8");
      return;
    }

    res.end(data);
  });
}

function listenOn(port) {
  const server = http.createServer(handleRequest);

  server.once("error", (error) => {
    if (error.code === "EADDRINUSE") {
      const nextPort = port + 1;
      console.log(`Port ${port} is busy, trying ${nextPort}...`);
      listenOn(nextPort);
      return;
    }

    console.error(error);
    process.exit(1);
  });

  server.listen(port, () => {
    console.log(`Trainw dev server running at http://127.0.0.1:${port}`);
    if (runtimeSupabaseConfig.url && runtimeSupabaseConfig.key) {
      console.log(`Trainw dev server injected Supabase config from ${runtimeSupabaseConfig.source}.`);
    } else {
      console.log("Trainw dev server did not find Supabase config to inject.");
    }
  });
}

listenOn(preferredPort);
