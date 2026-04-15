const fs = require('fs');
const path = require('path');

const rootDir = __dirname;
const distDir = path.join(rootDir, 'dist');

function readFileIfExists(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch (_error) {
    return null;
  }
}

function resolveSupabaseConfig() {
  const envUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || '';
  const envKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY || '';

  if (envUrl && envKey) {
    return { supabaseUrl: envUrl, supabaseAnonKey: envKey, source: 'environment' };
  }

  const candidateFiles = [
    path.join(rootDir, 'tw-coach-acc.html'),
    path.join(rootDir, 'dist', 'tw-coach-acc.html'),
  ];

  for (const candidate of candidateFiles) {
    const text = readFileIfExists(candidate);
    if (!text) continue;

    const urlMatch = text.match(/window\.__TRAINW_URL__\s*=\s*['"]([^'"]+)['"]/);
    const keyMatch = text.match(/window\.__TRAINW_KEY__\s*=\s*['"]([^'"]+)['"]/);

    if (!urlMatch || !keyMatch) continue;
    if (/%%SUPABASE_/i.test(urlMatch[1]) || /%%SUPABASE_/i.test(keyMatch[1])) continue;

    return {
      supabaseUrl: urlMatch[1],
      supabaseAnonKey: keyMatch[1],
      source: path.basename(candidate),
    };
  }

  return { supabaseUrl: '', supabaseAnonKey: '', source: 'missing' };
}

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
  '.git',
  '.vercel',
  'dist',
  'node_modules',
  'supabase',
]);

const ignoredFiles = new Set([
  'dev-server.js',
  'env-config.js',
  'package-lock.json',
  'package.json',
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
    'Trainw build: missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY',
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

function verifyRequiredHtmlFiles() {
  for (const fileName of requiredHtmlFiles) {
    const outputPath = path.join(distDir, fileName);

    if (!fs.existsSync(outputPath)) {
      throw new Error(`Trainw build: missing expected output file ${fileName}`);
    }

    const html = fs.readFileSync(outputPath, 'utf8');

    if (!html.includes('window.__TRAINW_URL__') || !html.includes('window.__TRAINW_KEY__')) {
      throw new Error(`Trainw build: config bootstrap is missing in ${fileName}`);
    }

    if (html.includes('%%SUPABASE_URL%%') || html.includes('%%SUPABASE_ANON_KEY%%')) {
      throw new Error(`Trainw build: unresolved Supabase placeholder remains in ${fileName}`);
    }
  }
}

resetDirectory(distDir);
copyTree(rootDir, distDir);
verifyRequiredHtmlFiles();

console.log(`Trainw build: generated dist with injected Supabase configuration from ${configSource}.`);
