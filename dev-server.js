const http = require("http");
const fs = require("fs");
const path = require("path");

const root = __dirname;
const preferredPort = Number(process.env.PORT || 3000);
const envFileCache = loadEnvFileConfig();

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

// FE-32 (Phase 1b): the only file types the dev server may serve. This is
// the same allow-list env-config.js uses for the production build (plus
// .map/.webmanifest/.woff/.woff2, which the build also copies). Anything
// else — .env, .sql, .md, .git internals — is never served.
const allowedExtensions = new Set([
  ...Object.keys(mimeTypes),
  ".map",
  ".webmanifest",
  ".woff",
  ".woff2",
]);

// FE-32: trees that are never served, even for an allowed extension.
const blockedFirstSegments = new Set(["database", "supabase"]);

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

// P1-6: same security headers as vercel.json, so local dev enforces the same
// policy as production. Keep the two in sync.
// - script-src has NO 'unsafe-inline'/'unsafe-eval': pages carry no inline
//   scripts (config lives in trainw-config.js) and no eval() is used.
// - style-src keeps 'unsafe-inline': the pages use inline style="..." attrs.
// - camera=(self): the gate terminal needs the camera for QR scanning.
const SECURITY_HEADERS = {
  "Content-Security-Policy":
    "default-src 'self'; " +
    "script-src 'self' https://cdn.jsdelivr.net https://unpkg.com https://cdnjs.cloudflare.com; " +
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " +
    "font-src 'self' https://fonts.gstatic.com; " +
    "img-src 'self' data: blob: https:; " +
    "media-src 'self' blob:; " +
    "connect-src 'self' https://*.supabase.co wss://*.supabase.co; " +
    "frame-src 'none'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'",
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
  "Permissions-Policy": "camera=(self), microphone=(), geolocation=()",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "strict-origin-when-cross-origin",
};

function readFileIfExists(filePath) {
  try {
    return fs.readFileSync(filePath, "utf8");
  } catch (_error) {
    return null;
  }
}

function parseEnvFile(text) {
  const values = {};
  const lines = String(text || "").split(/\r?\n/);

  for (const rawLine of lines) {
    const trimmed = rawLine.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const line = trimmed.startsWith("export ") ? trimmed.slice(7).trim() : trimmed;
    const equalsIndex = line.indexOf("=");
    if (equalsIndex <= 0) continue;

    const key = line.slice(0, equalsIndex).trim();
    let value = line.slice(equalsIndex + 1).trim();

    if (!key) continue;

    const hasMatchingQuotes =
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"));

    if (hasMatchingQuotes) {
      value = value.slice(1, -1);
    } else {
      const commentIndex = value.indexOf(" #");
      if (commentIndex >= 0) {
        value = value.slice(0, commentIndex).trim();
      }
    }

    values[key] = value.replace(/\\n/g, "\n");
  }

  return values;
}

function loadEnvFileConfig() {
  const files = [
    ".env",
    ".env.local",
    ".env.development",
    ".env.development.local",
    ".env.production",
    ".env.production.local",
  ];

  return files.reduce((acc, fileName) => {
    const filePath = path.join(root, fileName);
    const contents = readFileIfExists(filePath);
    if (!contents) return acc;
    return Object.assign(acc, parseEnvFile(contents));
  }, {});
}

function resolveConfigValue(keys) {
  for (const key of keys) {
    const envValue = String(process.env[key] || "").trim();
    if (envValue) return envValue;
    const fileValue = String(envFileCache[key] || "").trim();
    if (fileValue) return fileValue;
  }
  return "";
}

function isPlaceholderConfigValue(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (!normalized) return true;
  return (
    normalized.includes("%%supabase_") ||
    normalized.includes("example.supabase.co") ||
    normalized.includes("xyzcompany.supabase.co") ||
    normalized.includes("project-id.supabase.co") ||
    normalized === "example-anon-key" ||
    normalized === "publishable-or-anon-key" ||
    normalized === "public-anon-key" ||
    normalized.startsWith("your_")
  );
}

function hasUsableSupabaseConfig(url, key) {
  return !isPlaceholderConfigValue(url) && !isPlaceholderConfigValue(key);
}

function discoverSupabaseConfig() {
  const envUrl = resolveConfigValue(["NEXT_PUBLIC_SUPABASE_URL", "SUPABASE_URL"]);
  const envKey = resolveConfigValue(["NEXT_PUBLIC_SUPABASE_ANON_KEY", "SUPABASE_ANON_KEY"]);

  if (hasUsableSupabaseConfig(envUrl, envKey)) {
    return { url: envUrl, key: envKey, source: "environment" };
  }

  // FE-23 (Phase 1b): no HTML-scraping fallback any more. A previous dev
  // run succeeded by scraping the Supabase config out of a generated dist
  // copy or an HTML page — which silently re-used stale values. Without
  // environment config the dev server now fails loudly for /trainw-config.js
  // (see the handler below) instead of serving a scraped value.
  return { url: "", key: "", source: "missing" };
}

const runtimeSupabaseConfig = discoverSupabaseConfig();

// Turnstile flag (Phase 1b): only the literal value 'true' enables
// turnstiles; anything else (including unset) is OFF.
const turnstilesEnabled = resolveConfigValue(["TURNSTILES_ENABLED"]) === "true";

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
  res.writeHead(status, { ...SECURITY_HEADERS, ...headers });
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

    // FE-32: block dotfiles/dot-dirs (.env, .git, .next, .vercel) and the
    // database/ + supabase/ trees for every candidate, file or directory.
    const relative = path.relative(root, resolved);
    const segments = relative.split(path.sep);
    if (segments.some((segment) => segment.startsWith("."))) continue;
    if (blockedFirstSegments.has(segments[0])) continue;

    if (fs.existsSync(resolved)) {
      const stats = fs.statSync(resolved);
      if (stats.isDirectory()) {
        const indexFile = path.join(resolved, "index.html");
        if (fs.existsSync(indexFile)) return indexFile;
        continue;
      }
      // FE-32: only the allow-listed extensions are served.
      if (!allowedExtensions.has(path.extname(resolved).toLowerCase())) continue;
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

  // P1-6: serve the runtime config as an external script (same content
  // env-config.js writes into dist/trainw-config.js) so pages need no inline
  // <script> block and the CSP can forbid inline scripts outright.
  const requestPath = decodeURIComponent((req.url || "/").split("?")[0]);
  if (requestPath === "/trainw-config.js") {
    if (!runtimeSupabaseConfig.url || !runtimeSupabaseConfig.key) {
      send(res, 500, "// Trainw dev server: no Supabase config found (set NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY in .env).\n", { "Content-Type": "text/javascript; charset=utf-8" });
      return;
    }
    const configJs =
      "// Trainw runtime configuration — served by dev-server.js.\n" +
      `window.__TRAINW_URL__ = ${JSON.stringify(runtimeSupabaseConfig.url)};\n` +
      `window.__TRAINW_KEY__ = ${JSON.stringify(runtimeSupabaseConfig.key)};\n` +
      `window.__TRAINW_TURNSTILES_ENABLED__ = ${turnstilesEnabled};\n`;
    send(res, 200, configJs, { "Cache-Control": "no-store", "Content-Type": "text/javascript; charset=utf-8" });
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
      "Content-Type": contentType,
      ...SECURITY_HEADERS,
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

  return server;
}

if (require.main === module) {
  listenOn(preferredPort);
}

module.exports = {
  discoverSupabaseConfig,
  handleRequest,
  listenOn,
  replaceConfigPlaceholders,
  rewriteMap,
  safeResolve,
};
