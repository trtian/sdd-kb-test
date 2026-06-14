#!/usr/bin/env node
const fs = require('fs');
const http = require('http');
const https = require('https');
const { URL } = require('url');

function parseArgs(argv) {
  const args = {};
  for (const item of argv.slice(2)) {
    if (!item.startsWith('--')) continue;
    const eq = item.indexOf('=');
    if (eq === -1) args[item.slice(2)] = true;
    else args[item.slice(2, eq)] = item.slice(eq + 1);
  }
  return args;
}

function requestJson(url, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const lib = u.protocol === 'https:' ? https : http;
    const payload = JSON.stringify(body);
    const req = lib.request(
      {
        hostname: u.hostname,
        port: u.port || (u.protocol === 'https:' ? 443 : 80),
        path: u.pathname,
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }
      },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
          catch (e) { reject(new Error(data)); }
        });
      }
    );
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

async function main() {
  const args = parseArgs(process.argv);
  const apiBase = (process.env.ENGINEERING_KB_API || args['api-base'] || 'http://localhost:8090/api').replace(/\/$/, '');
  const projectId = args['project-id'] || process.env.ENGINEERING_KB_PROJECT_ID || '1';
  const hintsPath = args['scope-hints-path'];
  const gitCommit = args['git-commit'] || 'local';

  let scopeHintsJson = null;
  if (hintsPath && fs.existsSync(hintsPath)) {
    scopeHintsJson = fs.readFileSync(hintsPath, 'utf8');
  }

  const { status, body } = await requestJson(
    `${apiBase}/projects/${projectId}/conflict-suggestions`,
    { gitCommit, scopeHintsJson }
  );
  if (status >= 400 || body.code !== 0) {
    console.log(JSON.stringify({ ok: false, error: body.message || status }));
    process.exit(1);
  }
  console.log(JSON.stringify({ ok: true, ...body.data }, null, 2));
}

main().catch((e) => {
  console.log(JSON.stringify({ ok: false, error: e.message }));
  process.exit(1);
});
