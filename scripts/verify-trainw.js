const fs = require('fs');
const path = require('path');
const http = require('http');
const vm = require('vm');

const rootDir = path.resolve(__dirname, '..');
const verifyPort = 3100;
const { handleRequest } = require(path.join(rootDir, 'dev-server.js'));

const routeExpectations = [
  ['/', 'Trainw -'],
  ['/role', 'Bienvenue'],
  ['/login?role=gym_owner', 'Connexion'],
  ['/admin', 'Tableau de bord'],
  ['/coach', 'Trainw'],
  ['/client', 'Trainw'],
  ['/dashboard', 'Tableau de bord'],
  ['/dashboard/gym', 'Tableau de bord'],
  ['/dashboard/coach', 'Trainw'],
  ['/dashboard/client', 'Trainw'],
  ['/gate', 'TRAINW Gate'],
];

const localRoutes = new Set([
  '/role',
  '/login',
  '/admin',
  '/dashboard',
  '/dashboard/gym',
  '/dashboard/coach',
  '/dashboard/client',
  '/coach',
  '/client',
  '/gate',
]);

const jsFiles = [
  'dev-server.js',
  'env-config.js',
  'gate-terminal.js',
  'index.js',
  'trainw-core.js',
  'trainw-tenant-utils.js',
  'trainw-translations.js',
  'tw-client-acc.js',
  'tw-client-pilot.js',
  'tw-coach-acc.js',
  'tw-gym-acc-v17.js',
  'tw-gym-acc.js',
  'tw-gym-pilot.js',
  'tw-login.js',
  'tw-role.js',
];

const htmlFiles = [
  'index.html',
  'tw-role.html',
  'tw-login.html',
  'tw-gym-acc.html',
  'tw-coach-acc.html',
  'tw-client-acc.html',
  'gate-terminal.html',
];

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function verifyJsSyntax() {
  for (const relativeFile of jsFiles) {
    const absoluteFile = path.join(rootDir, relativeFile);
    assert(fs.existsSync(absoluteFile), `Missing JS file: ${relativeFile}`);
    const source = fs.readFileSync(absoluteFile, 'utf8');

    try {
      new vm.Script(source, { filename: relativeFile });
    } catch (error) {
      throw new Error(`JS syntax failed for ${relativeFile}\n${error.message}`);
    }
  }
}

function verifyHtmlAssets() {
  const attributeRegex = /(?:src|href)="(?!https?:|mailto:|tel:|#|javascript:)([^"]+)"/g;

  for (const relativeFile of htmlFiles) {
    const absoluteFile = path.join(rootDir, relativeFile);
    assert(fs.existsSync(absoluteFile), `Missing HTML file: ${relativeFile}`);
    const html = fs.readFileSync(absoluteFile, 'utf8');

    let match;
    while ((match = attributeRegex.exec(html)) !== null) {
      const originalRef = match[1];
      const ref = originalRef.split('?')[0];
      if (!ref) continue;
      if (localRoutes.has(ref)) continue;

      const targetPath = path.join(rootDir, ref.replace(/^\/+/, ''));
      assert(fs.existsSync(targetPath), `Broken asset ref in ${relativeFile}: ${originalRef}`);
    }
  }
}

function verifyVersionNames() {
  const filesToScan = [
    ...htmlFiles,
    ...jsFiles,
    'index.css',
    'trainw-enhancements.css',
    'trainw-v17.css',
    'tw-client-acc-v17.css',
    'tw-client-acc.css',
    'tw-coach-acc-v17.css',
    'tw-coach-acc.css',
    'tw-gym-acc-v17.css',
    'tw-gym-acc.css',
    'tw-login.css',
    'tw-role.css',
  ];

  for (const relativeFile of filesToScan) {
    const absoluteFile = path.join(rootDir, relativeFile);
    if (!fs.existsSync(absoluteFile)) continue;
    const content = fs.readFileSync(absoluteFile, 'utf8');
    assert(!/\bV14\b|\bv14\b|\bV16\b|\bv16\b/.test(content), `Legacy version reference found in ${relativeFile}`);
  }
}

function request(pathname) {
  return new Promise((resolve, reject) => {
    const req = http.get(
      {
        host: '127.0.0.1',
        path: pathname,
        port: verifyPort,
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          resolve({
            body: Buffer.concat(chunks).toString('utf8'),
            statusCode: res.statusCode || 0,
          });
        });
      },
    );

    req.on('error', reject);
  });
}

async function waitForServer() {
  const startedAt = Date.now();
  let lastError = null;

  while (Date.now() - startedAt < 10000) {
    try {
      const response = await request('/');
      if (response.statusCode === 200) {
        return;
      }
      lastError = new Error(`Unexpected status while waiting for server: ${response.statusCode}`);
    } catch (error) {
      lastError = error;
    }

    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  throw lastError || new Error('Timed out waiting for dev server.');
}

async function verifyRoutes() {
  const server = http.createServer(handleRequest);

  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(verifyPort, '127.0.0.1', resolve);
    });

    await waitForServer();

    for (const [pathname, marker] of routeExpectations) {
      const response = await request(pathname);
      assert(response.statusCode === 200, `Route ${pathname} returned ${response.statusCode}`);
      assert(
        response.body.includes(marker),
        `Route ${pathname} is missing expected marker: ${marker}`,
      );
    }

    const missingPage = await request('/missing-page');
    assert(
      missingPage.statusCode === 404,
      `Expected /missing-page to return 404, got ${missingPage.statusCode}`,
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function main() {
  verifyJsSyntax();
  verifyHtmlAssets();
  verifyVersionNames();
  await verifyRoutes();
  console.log('Trainw verify: all checks passed.');
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
