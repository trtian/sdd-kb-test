'use strict';

/**
 * PR diff 结构化分析 — 供 opsx-kb-pr-diff / claude -p 使用
 * Usage: node analyze-diff.cjs --diff-path=.kb-ci/pr-diff.patch [--code-repo=.]
 */
const fs = require('fs');
const path = require('path');

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

function readJson(p) {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
}

function parseDiffFiles(diffText) {
  const files = [];
  const re = /^diff --git a\/(.+?) b\/(.+)$/gm;
  let m;
  while ((m = re.exec(diffText))) {
    files.push({ from: m[1], to: m[2], path: m[2] });
  }
  return files;
}

function extractSpecHeadings(patch, filePath) {
  const headings = [];
  const lines = patch.split('\n');
  let inFile = false;
  for (const line of lines) {
    if (line.startsWith('diff --git') && line.includes(filePath)) inFile = true;
    else if (line.startsWith('diff --git') && inFile) break;
    if (!inFile) continue;
    if ((line.startsWith('+') || line.startsWith('-')) && !line.startsWith('+++') && !line.startsWith('---')) {
      const hm = line.slice(1).match(/^(#{4,5})\s+(.+)/);
      if (hm) headings.push({ level: hm[1].length, text: hm[2].trim(), op: line[0] });
    }
  }
  return headings;
}

function mapCapabilities(changedPaths, mapFile) {
  const map = readJson(mapFile) || readYamlCapabilities(mapFile);
  if (!map) return [];
  const caps = [];
  for (const [capId, cfg] of Object.entries(map)) {
    const patterns = cfg.path_patterns || cfg.sdd_paths || [];
    for (const p of changedPaths) {
      const norm = p.replace(/\\/g, '/');
      if (patterns.some((pat) => matchGlob(norm, pat))) {
        caps.push(capId);
        break;
      }
    }
  }
  return [...new Set(caps)];
}

function readYamlCapabilities() {
  return null; // map loaded via scope hints instead
}

function matchGlob(str, pat) {
  const rx = pat.replace(/\*\*/g, '.*').replace(/\*/g, '[^/]*');
  return new RegExp(rx).test(str);
}

function main() {
  const args = parseArgs(process.argv);
  const codeRepo = args['code-repo'] || '.';
  const diffPath = args['diff-path'] || path.join(codeRepo, '.kb-ci/pr-diff.patch');
  const hintsPath = args['scope-hints-path'] || path.join(codeRepo, '.kb-ci/gitnexus-scope-hints.json');

  if (!fs.existsSync(diffPath)) {
    console.log(JSON.stringify({ ok: false, error: `diff not found: ${diffPath}` }));
    process.exit(1);
  }

  const diffText = fs.readFileSync(diffPath, 'utf8');
  const files = parseDiffFiles(diffText);
  const openspec = files.filter((f) => f.path.includes('openspec/') && f.path.endsWith('.md'));
  const code = files.filter((f) => /\.(java|kt|ts|js|go)$/.test(f.path));
  const sdd = files.filter((f) => f.path.includes('openspec/'));

  const headingChanges = [];
  for (const f of openspec) {
    for (const h of extractSpecHeadings(diffText, f.path)) {
      headingChanges.push({ file: f.path, ...h });
    }
  }

  const hints = readJson(hintsPath);
  const capabilities =
    hints?.capabilities ||
    hints?.matchedCapabilities ||
    mapCapabilities(
      files.map((f) => f.path),
      path.join(codeRepo, '.kb-ci/code-capability-map.yml')
    );

  const searchQueries = headingChanges
    .filter((h) => h.level >= 4 && h.op === '+')
    .map((h) => (h.level === 5 ? h.text : `需求项：${h.text.replace(/^需求项：/, '')}`))
    .slice(0, 5);

  if (!searchQueries.length) {
    searchQueries.push('需求项：填充前必填字段校验');
  }

  const sddOnly = sdd.length > 0 && code.length === 0;
  const codeOnly = code.length > 0 && sdd.length === 0;
  let diffVerdict = 'pass';
  if (code.length > 0 && sdd.length === 0) diffVerdict = 'warn';
  if (code.length > 0 && sdd.length > 0) diffVerdict = 'pass';

  console.log(
    JSON.stringify(
      {
        ok: true,
        summary: {
          filesChanged: files.length,
          openspecFiles: openspec.length,
          codeFiles: code.length,
          headingChanges: headingChanges.length,
          capabilities,
          sddOnly,
          codeOnly,
        },
        files: files.map((f) => f.path),
        headingChanges,
        searchQueries,
        diffVerdict,
        hint:
          diffVerdict === 'warn'
            ? '代码变更未伴随 SDD 更新，建议补充 openspec'
            : 'diff 已映射到 capability / 检索 query',
      },
      null,
      2
    )
  );
}

main();
