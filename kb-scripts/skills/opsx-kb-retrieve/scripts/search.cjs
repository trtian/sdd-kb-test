#!/usr/bin/env node
'use strict';

/**
 * Engineering KB 检索 CLI（兼容入口，推荐 ./bin/kb search）
 * Usage: node search.cjs --question="..." [--project-id=1]
 */

const path = require('path');
const { parseArgs, configFromEnv, apiCall, ok, fail } = require('../../opsx-kb-cli/scripts/lib/client.cjs');

async function main() {
  const args = parseArgs(process.argv);
  const question = args.question || args.q;
  if (!question) fail('missing --question');
  const cfg = configFromEnv(args);
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

main().catch((e) => fail(e.message));
