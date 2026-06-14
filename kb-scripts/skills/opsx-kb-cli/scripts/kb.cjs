#!/usr/bin/env node
'use strict';

/**
 * Engineering KB unified CLI
 *
 * Usage:
 *   node kb.cjs search --question="汇率自动计算"
 *   node kb.cjs ingest --source-path=/path/openspec --git-commit=abc
 *   node kb.cjs graph status|rebuild|network --logical-id=...
 *   node kb.cjs health
 *   node kb.cjs auth login
 *   node kb.cjs loop [--skip-graph] [--skip-iteration]
 */

const { spawnSync } = require('child_process');
const path = require('path');
const { parseArgs, configFromEnv, apiCall, login, ok, fail } = require('./lib/client.cjs');

const args = parseArgs(process.argv);
const cmd = args._[0];

async function cmdHealth(cfg) {
  const { request } = require('./lib/client.cjs');
  const { status, body } = await request('GET', `${cfg.apiBase}/health`, { timeoutMs: 10000 });
  if (status >= 400 || body?.code !== 0) fail(body?.message || `HTTP ${status}`);
  ok({ health: body.data });
}

async function cmdAuth(cfg) {
  const sub = args._[1] || 'login';
  if (sub !== 'login') fail(`unknown auth subcommand: ${sub}`);
  const token = await login(cfg);
  ok({ token, hint: 'export ENGINEERING_KB_TOKEN=<token>' });
}

async function cmdSearch(cfg) {
  const question = args.question || args.q;
  if (!question) fail('missing --question');
  const data = await apiCall(cfg, 'POST', `/projects/${cfg.projectId}/search`, { query: question });
  ok({
    question,
    projectId: cfg.projectId,
    evidenceLevel: data.evidenceLevel,
    hint: data.hint,
    hits: data.hits || [],
    historicalHints: data.historicalHints || [],
    graphSource: (data.hits || []).find((h) => h.graphNetwork)?.graphNetwork?.source || null,
  });
}

async function cmdIngest(cfg) {
  const sourcePath = args['source-path'];
  if (!sourcePath) fail('missing --source-path');
  const payload = {
    sourcePath,
    gitCommit: args['git-commit'] || 'local',
    headingLevel: parseInt(args['heading-level'] || '4', 10),
    gitBranch: args['git-branch'] || 'main',
    ciPassed: args['ci-passed'] !== 'false',
  };
  if (args['scope-hints-path']) payload.scopeHintsPath = args['scope-hints-path'];
  const job = await apiCall(cfg, 'POST', `/projects/${cfg.projectId}/ingest`, payload);
  ok({ job });
}

async function cmdGraph(cfg) {
  const sub = args._[1] || 'status';
  if (sub === 'status') {
    const data = await apiCall(cfg, 'GET', `/projects/${cfg.projectId}/graph/status`);
    ok({ graph: data });
    return;
  }
  if (sub === 'rebuild') {
    const data = await apiCall(cfg, 'POST', `/projects/${cfg.projectId}/graph/rebuild`);
    ok({ graph: data });
    return;
  }
  if (sub === 'network') {
    const logicalId = args['logical-id'];
    if (!logicalId) fail('missing --logical-id');
    const depth = parseInt(args.depth || '2', 10);
    const data = await apiCall(
      cfg,
      'GET',
      `/projects/${cfg.projectId}/graph/sections/${encodeURIComponent(logicalId)}/network?depth=${depth}`
    );
    ok({ network: data });
    return;
  }
  fail(`unknown graph subcommand: ${sub}`);
}

async function cmdSections(cfg) {
  const limit = args.limit || '50';
  const data = await apiCall(cfg, 'GET', `/projects/${cfg.projectId}/sections?limit=${limit}`);
  ok({ count: data.length, sections: data });
}

function cmdLoop(cfg) {
  const root = path.resolve(__dirname, '../../..');
  const loopScript = path.join(root, 'ci/local-sdd-loop.sh');
  const env = { ...process.env };
  if (args['skip-graph']) env.SKIP_GRAPH = 'true';
  if (args['skip-iteration']) env.SKIP_ITERATION = 'true';
  if (args['skip-supersede']) env.SKIP_SUPERSEDE = 'true';
  env.ENGINEERING_KB_API = cfg.apiBase;
  env.ENGINEERING_KB_PROJECT_ID = cfg.projectId;
  const r = spawnSync('bash', [loopScript], { stdio: 'inherit', env, cwd: root });
  process.exit(r.status ?? 1);
}

function printHelp() {
  console.log(`Engineering KB CLI

Usage: kb <command> [options]

Commands:
  health                         API health check
  auth login                     Obtain Bearer token
  search --question="..."        Retrieve current SDD sections (+ graphNetwork)
  ingest --source-path=PATH      Ingest OpenSpec markdown directory
  graph status|rebuild|network   AGE graph operations
  sections [--limit=50]          List section manifest
  loop [--skip-graph]            Run ci/local-sdd-loop.sh end-to-end

Environment:
  ENGINEERING_KB_API           default http://localhost:8090/api
  ENGINEERING_KB_PROJECT_ID      default 1
  ENGINEERING_KB_TOKEN           Bearer token (or auto login)
  E2E_PHONE / E2E_PASSWORD       local login credentials
`);
}

async function main() {
  if (!cmd || cmd === 'help' || args.help) {
    printHelp();
    return;
  }
  const cfg = configFromEnv(args);
  if (cmd === 'health') return cmdHealth(cfg);
  if (cmd === 'auth') return cmdAuth(cfg);
  if (cmd === 'search') return cmdSearch(cfg);
  if (cmd === 'ingest') return cmdIngest(cfg);
  if (cmd === 'graph') return cmdGraph(cfg);
  if (cmd === 'sections') return cmdSections(cfg);
  if (cmd === 'loop') return cmdLoop(cfg);
  fail(`unknown command: ${cmd}`);
}

main().catch((e) => fail(e.message));
