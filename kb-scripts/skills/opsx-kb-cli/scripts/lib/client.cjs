'use strict';

const http = require('http');
const https = require('https');
const { URL } = require('url');

function parseArgs(argv) {
  const args = { _: [] };
  for (const item of argv.slice(2)) {
    if (!item.startsWith('--')) {
      args._.push(item);
      continue;
    }
    const eq = item.indexOf('=');
    if (eq === -1) args[item.slice(2)] = true;
    else args[item.slice(2, eq)] = item.slice(eq + 1);
  }
  return args;
}

function configFromEnv(args = {}) {
  return {
    apiBase: (args['api-base'] || process.env.ENGINEERING_KB_API || 'http://localhost:8090/api').replace(/\/$/, ''),
    projectId: args['project-id'] || process.env.ENGINEERING_KB_PROJECT_ID || '1',
    tenantKey: args['tenant-key'] || process.env.ENGINEERING_KB_TENANT_KEY || 'team-erp-fi',
    token: args.token || process.env.ENGINEERING_KB_TOKEN || process.env.E2E_AUTH_TOKEN || '',
    phone: args.phone || process.env.E2E_PHONE || '18758284088',
    password: args.password || process.env.E2E_PASSWORD || '123456',
    timeoutMs: parseInt(args.timeout || process.env.ENGINEERING_KB_TIMEOUT_MS || '120000', 10),
  };
}

function request(method, url, { body, token, timeoutMs = 120000 } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const lib = u.protocol === 'https:' ? https : http;
    const payload = body != null ? JSON.stringify(body) : null;
    const headers = { Accept: 'application/json' };
    if (payload) {
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = Buffer.byteLength(payload);
    }
    if (token) headers.Authorization = `Bearer ${token}`;

    const req = lib.request(
      {
        hostname: u.hostname,
        port: u.port || (u.protocol === 'https:' ? 443 : 80),
        path: u.pathname + u.search,
        method,
        headers,
        timeout: timeoutMs,
      },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, body: data ? JSON.parse(data) : null, raw: data });
          } catch (e) {
            reject(new Error(`Invalid JSON (${res.statusCode}): ${data.slice(0, 300)}`));
          }
        });
      }
    );
    req.on('timeout', () => req.destroy(new Error(`timeout after ${timeoutMs}ms: ${method} ${url}`)));
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function login(cfg) {
  const { status, body } = await request('POST', `${cfg.apiBase}/auth/login`, {
    body: { phone: cfg.phone, password: cfg.password },
    timeoutMs: 15000,
  });
  if (status >= 400 || !body || body.code !== 0) {
    throw new Error(body?.message || `login failed HTTP ${status}`);
  }
  return body.data.token;
}

async function withAuth(cfg, fn) {
  let token = cfg.token;
  if (!token) {
    try {
      token = await login(cfg);
    } catch (e) {
      // auth may be disabled locally
    }
  }
  return fn(token);
}

async function apiCall(cfg, method, path, body) {
  return withAuth(cfg, async (token) => {
    const { status, body: resp } = await request(method, `${cfg.apiBase}${path}`, {
      body,
      token,
      timeoutMs: cfg.timeoutMs,
    });
    if (status >= 400 || !resp || resp.code !== 0) {
      const err = new Error(resp?.message || `HTTP ${status}`);
      err.status = status;
      err.response = resp;
      throw err;
    }
    return resp.data;
  });
}

function fail(msg, code = 1) {
  console.log(JSON.stringify({ ok: false, error: msg }));
  process.exit(code);
}

function ok(data) {
  console.log(JSON.stringify({ ok: true, ...data }, null, 2));
}

module.exports = { parseArgs, configFromEnv, request, login, withAuth, apiCall, fail, ok };
