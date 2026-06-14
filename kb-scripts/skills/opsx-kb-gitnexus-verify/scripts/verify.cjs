'use strict';

/**
 * KB current 规则 + 代码仓比对（GitNexus scope / 路径映射辅助）
 */
const fs = require('fs');
const path = require('path');
const { parseArgs, configFromEnv, apiCall, ok, fail } = require('../../opsx-kb-cli/scripts/lib/client.cjs');

function readJson(p) {
  if (!p || !fs.existsSync(p)) return null;
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function walkFiles(dir, patterns, limit = 80) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  function walk(d, depth) {
    if (depth > 6 || out.length >= limit) return;
    for (const name of fs.readdirSync(d)) {
      if (name.startsWith('.') || name === 'node_modules') continue;
      const full = path.join(d, name);
      const st = fs.statSync(full);
      if (st.isDirectory()) walk(full, depth + 1);
      else if (/\.(java|kt|ts|js|go)$/.test(name)) out.push(full);
    }
  }
  walk(dir, 0);
  return out.filter((f) => patterns.some((p) => f.includes(p.replace(/\*\*/g, '').replace(/\*/g, '')) || true));
}

function scanCodeForPhrases(codeRepo, phrases) {
  const src = path.join(codeRepo, 'src');
  const files = walkFiles(src, ['account', 'document', 'head']);
  const hits = [];
  for (const file of files) {
    const content = fs.readFileSync(file, 'utf8');
    for (const phrase of phrases) {
      if (phrase && content.includes(phrase)) {
        hits.push({ file: path.relative(codeRepo, file), phrase });
      }
    }
  }
  return hits;
}

async function main() {
  const args = parseArgs(process.argv);
  const question = args.question || args.q || '需求项：填充前必填字段校验';
  const codeRepo = args['code-repo'] || process.env.CODE_REPO || '.';
  const cfg = configFromEnv(args);

  const searchData = await apiCall(cfg, 'POST', `/projects/${cfg.projectId}/search`, { query: question });
  const hits = searchData.hits || [];
  if (!hits.length) {
    fail(`NO_CURRENT_EVIDENCE for: ${question}`);
  }

  const top = hits[0];
  const snippets = hits.slice(0, 5).map((h) => ({
    logicalSectionId: h.logicalSectionId,
    headingPath: h.headingPath,
    status: h.status,
    evidenceRole: h.evidenceRole,
    snippet: (h.snippet || '').slice(0, 200),
  }));

  const hints = readJson(args['scope-hints-path']);
  const changedFiles = hints?.changedFiles || hints?.files || [];
  const capabilities = hints?.capabilities || hints?.matchedCapabilities || [];

  const expectPhrases = [];
  for (const h of hits.slice(0, 3)) {
    const sn = h.snippet || '';
    const m = sn.match(/BusinessException\("[^"]+"\)/g) || sn.match(/凭证日期不能为空|过账日期不能为空/g);
    if (m) expectPhrases.push(...m.map((x) => x.replace(/BusinessException\("|"\)/g, '')));
  }
  if (!expectPhrases.length) expectPhrases.push('凭证日期不能为空', '过账日期不能为空');

  const codeHits = scanCodeForPhrases(codeRepo, expectPhrases);
  const matched = expectPhrases.filter((p) => codeHits.some((c) => c.phrase.includes(p) || p.includes(c.phrase)));
  const missing = expectPhrases.filter((p) => !matched.includes(p));

  let verdict = 'pass';
  if (searchData.evidenceLevel === 'NO_CURRENT_EVIDENCE') verdict = 'fail';
  else if (missing.length && codeHits.length === 0) verdict = 'warn';
  else if (missing.length) verdict = 'warn';

  ok({
    question,
    evidenceLevel: searchData.evidenceLevel,
    topHit: {
      logicalSectionId: top.logicalSectionId,
      headingPath: top.headingPath,
      gitCommit: top.gitCommit,
    },
    snippets,
    scope: { changedFiles, capabilities },
    codeCompare: {
      expectPhrases,
      codeHits,
      matched,
      missing,
    },
    verdict,
    hint: verdict === 'pass'
      ? 'KB current 规则与代码关键字一致'
      : '代码与 current SDD 可能不一致，请人工或 claude -p 复核',
  });
}

main().catch((e) => fail(e.message));
