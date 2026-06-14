#!/usr/bin/env node
'use strict';

/**
 * Engineering KB ingest CLI（兼容入口，推荐 ./bin/kb ingest）
 */

const { parseArgs, configFromEnv, apiCall, ok, fail } = require('../../opsx-kb-cli/scripts/lib/client.cjs');

async function main() {
  const args = parseArgs(process.argv);
  const sourcePath = args['source-path'];
  if (!sourcePath) fail('missing --source-path');
  const cfg = configFromEnv(args);
  const payload = {
    sourcePath,
    gitCommit: args['git-commit'] || 'local',
    headingLevel: parseInt(args['heading-level'] || '4', 10),
    gitBranch: args['git-branch'] || process.env.CI_COMMIT_REF_NAME || 'main',
    ciPassed: args['ci-passed'] !== 'false',
  };
  if (args['scope-hints-path']) payload.scopeHintsPath = args['scope-hints-path'];
  const job = await apiCall(cfg, 'POST', `/projects/${cfg.projectId}/ingest`, payload);
  ok({ job });
}

main().catch((e) => fail(e.message));
