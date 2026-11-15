const fs = require('fs');
const path = require('path');

const rootDir = __dirname;
const distDir = path.join(rootDir, 'dist');
const envFileCache = loadEnvFileConfig();

function readFileIfExists(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch (_error) {
    return null;
  }
}

function parseEnvFile(text) {
  const values = {};
  const lines = String(text || '').split(/\r?\n/);

  for (const rawLine of lines) {
    const trimmed = rawLine.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    const line = trimmed.startsWith('export ') ? trimmed.slice(7).trim() : trimmed;
    const equalsIndex = line.indexOf('=');
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
      const commentIndex = value.indexOf(' #');
      if (commentIndex >= 0) {
        value = value.slice(0, commentIndex).trim();
      }
    }

    values[key] = value.replace(/\\n/g, '\n');
  }

  return values;
}

function loadEnvFileConfig() {
  const files = [
    '.env',
    '.env.local',
    '.env.development',
    '.env.development.local',
    '.env.production',
    '.env.production.local',
  ];

  return files.reduce((acc, fileName) => {
    const filePath = path.join(rootDir, fileName);
    const contents = readFileIfExists(filePath);
    if (!contents) return acc;
    return Object.assign(acc, parseEnvFile(contents));
  }, {});
}

function resolveConfigValue(keys) {
  for (const key of keys) {
    const envValue = String(process.env[key] || '').trim();
    if (envValue) return envValue;
    const fileValue = String(envFileCache[key] || '').trim();
    if (fileValue) return fileValue;
  }
  return '';
}

function isPlaceholderConfigValue(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (!normalized) return true;
  return (
    normalized.includes('%%supabase_') ||
    normalized.includes('example.supabase.co') ||
    normalized.includes('xyzcompany.supabase.co') ||
    normalized.includes('project-id.supabase.co') ||
    normalized === 'example-anon-key' ||
    normalized === 'publishable-or-anon-key' ||
    normalized === 'public-anon-key' ||
    normalized.startsWith('your_')
  );
}

function hasUsableSupabaseConfig(url, key) {
  return !isPlaceholderConfigValue(url) && !isPlaceholderConfigValue(key);
}

function resolveSupabaseConfig() {
  const envUrl = resolveConfigValue(['NEXT_PUBLIC_SUPABASE_URL', 'SUPABASE_URL']);
  const envKey = resolveConfigValue(['NEXT_PUBLIC_SUPABASE_ANON_KEY', 'SUPABASE_ANON_KEY']);

  if (hasUsableSupabaseConfig(envUrl, envKey)) {
    return { supabaseUrl: envUrl, supabaseAnonKey: envKey, source: 'environment' };
  }

  // FE-23 (Phase 1b): no HTML-scraping fallback any more. A previous build
  // succeeded by scraping the Supabase config out of a generated dist copy
  // or an HTML page — which silently re-used stale/placeholder values. If
  // the environment does not provide the config, the build now fails loudly
  // below (missing NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY)
  // instead of building with a scraped value.
  return { supabaseUrl: '', supabaseAnonKey: '', source: 'missing' };
}

// Turnstile flag (Phase 1b, user requirement 2026-11-15): only the literal
// value 'true' enables turnstiles; anything else (including unset) is OFF.
const turnstilesEnabled = resolveConfigValue(['TURNSTILES_ENABLED']) === 'true';

const { supabaseUrl, supabaseAnonKey, source: configSource } = resolveSupabaseConfig();

const requiredHtmlFiles = new Set([
  'gate-terminal.html',
  'tw-gym-acc.html',
  'tw-coach-acc.html',
  'tw-client-acc.html',
  'tw-login.html',
  'tw-role.html',
]);

const ignoredDirectories = new Set([
  '.next',
  '.git',
  '.vercel',
  'database',
  'dist',
  'docs',
  'node_modules',
  'public',
  'scripts',
  'src',
  'supabase',
]);

const ignoredFiles = new Set([
  'dev-server.js',
  'env-config.js',
  'package-lock.json',
  'package.json',
  // P1-6: trainw-config.js is generated explicitly below (with resolved values),
  // never copied verbatim — the root copy only holds %%...%% placeholders.
  'trainw-config.js',
  'vercel.json',
]);

const ignoredExtensions = new Set([
  '.md',
  '.sql',
]);

const allowedExtensions = new Set([
  '.css',
  '.gif',
  '.html',
  '.ico',
  '.jpeg',
  '.jpg',
  '.js',
  '.json',
  '.map',
  '.png',
  '.svg',
  '.txt',
  '.webmanifest',
  '.webp',
  '.woff',
  '.woff2',
]);

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Trainw build: missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY. ' +
      'Set both in Vercel (Project Settings > Environment Variables) using the values from ' +
      'Supabase (Project Settings > API) for the current project. The build refuses to ' +
      'reuse a stale key from a previous dist copy.',
  );
}

function resetDirectory(targetDir) {
  fs.rmSync(targetDir, { recursive: true, force: true });
  fs.mkdirSync(targetDir, { recursive: true });
}

function shouldCopyFile(fileName) {
  if (ignoredFiles.has(fileName)) {
    return false;
  }

  const extension = path.extname(fileName).toLowerCase();

  if (ignoredExtensions.has(extension)) {
    return false;
  }

  return allowedExtensions.has(extension);
}

function replaceConfigPlaceholders(htmlSource) {
  return htmlSource
    .replace(/'%%SUPABASE_URL%%'/g, JSON.stringify(supabaseUrl))
    .replace(/'%%SUPABASE_ANON_KEY%%'/g, JSON.stringify(supabaseAnonKey))
    .replace(/%%SUPABASE_URL%%/g, supabaseUrl)
    .replace(/%%SUPABASE_ANON_KEY%%/g, supabaseAnonKey);
}

function copyTree(sourceDir, targetDir, relativeDir = '') {
  const entries = fs.readdirSync(sourceDir, { withFileTypes: true });

  for (const entry of entries) {
    const sourcePath = path.join(sourceDir, entry.name);
    const relativePath = path.join(relativeDir, entry.name);
    const targetPath = path.join(targetDir, entry.name);

    if (entry.isDirectory()) {
      if (ignoredDirectories.has(entry.name)) {
        continue;
      }

      fs.mkdirSync(targetPath, { recursive: true });
      copyTree(sourcePath, targetPath, relativePath);
      continue;
    }

    if (!shouldCopyFile(entry.name)) {
      continue;
    }

    if (path.extname(entry.name).toLowerCase() === '.html') {
      const originalHtml = fs.readFileSync(sourcePath, 'utf8');
      const transformedHtml = replaceConfigPlaceholders(originalHtml);

      fs.writeFileSync(targetPath, transformedHtml, 'utf8');
      continue;
    }

    fs.copyFileSync(sourcePath, targetPath);
  }
}

function writeConfigFile() {
  // P1-6: the Supabase config lives in an external file (trainw-config.js) so
  // pages no longer need an inline <script> block — the CSP can forbid
  // inline scripts outright. The committed root copy holds only placeholders.
  const configJs = [
    '// Trainw runtime configuration — generated by env-config.js at build time.',
    `window.__TRAINW_URL__ = ${JSON.stringify(supabaseUrl)};`,
    `window.__TRAINW_KEY__ = ${JSON.stringify(supabaseAnonKey)};`,
    // Turnstile flag (Phase 1b): only the literal 'true' in the build
    // environment enables turnstiles; default is false (off).
    `window.__TRAINW_TURNSTILES_ENABLED__ = ${turnstilesEnabled};`,
    '',
  ].join('\n');

  fs.writeFileSync(path.join(distDir, 'trainw-config.js'), configJs, 'utf8');
}

function verifyRequiredHtmlFiles() {
  // P1-6: the config bootstrap is trainw-config.js, not an inline script.
  const configPath = path.join(distDir, 'trainw-config.js');
  if (!fs.existsSync(configPath)) {
    throw new Error('Trainw build: missing expected output file trainw-config.js');
  }
  const configJs = fs.readFileSync(configPath, 'utf8');
  if (!configJs.includes('window.__TRAINW_URL__') || !configJs.includes('window.__TRAINW_KEY__')) {
    throw new Error('Trainw build: config bootstrap is missing in trainw-config.js');
  }
  if (!configJs.includes('window.__TRAINW_TURNSTILES_ENABLED__')) {
    throw new Error('Trainw build: turnstile flag is missing in trainw-config.js');
  }
  if (configJs.includes('%%SUPABASE_URL%%') || configJs.includes('%%SUPABASE_ANON_KEY%%')) {
    throw new Error('Trainw build: unresolved Supabase placeholder remains in trainw-config.js');
  }

  for (const fileName of requiredHtmlFiles) {
    const outputPath = path.join(distDir, fileName);

    if (!fs.existsSync(outputPath)) {
      throw new Error(`Trainw build: missing expected output file ${fileName}`);
    }

    const html = fs.readFileSync(outputPath, 'utf8');

    if (!html.includes('trainw-config.js')) {
      throw new Error(`Trainw build: config script is missing in ${fileName}`);
    }

    // P1-6: no page may carry the config as an inline script any more.
    if (/window\.__TRAINW_(URL|KEY)__\s*=/.test(html)) {
      throw new Error(`Trainw build: inline config script remains in ${fileName}`);
    }

    if (html.includes('%%SUPABASE_URL%%') || html.includes('%%SUPABASE_ANON_KEY%%')) {
      throw new Error(`Trainw build: unresolved Supabase placeholder remains in ${fileName}`);
    }
  }
}

resetDirectory(distDir);
copyTree(rootDir, distDir);
writeConfigFile();
verifyRequiredHtmlFiles();

console.log(`Trainw build: generated dist with injected Supabase configuration from ${configSource}.`);
