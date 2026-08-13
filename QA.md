<!-- tools: Bash,Read -->
# QA: clickhouse bag

ClickHouse Barry bag — wraps ClickHouse Cloud MCP, clickhousectl CLI tools, and official agent skills.

## Requirements

- `node` (v18+)
- `pnpm`
- `clickhousectl` installed and authenticated (`clickhousectl cloud auth login`)

## Setup

```bash
cd /Users/tyler/repos/bags/clickhouse && pnpm install 2>&1 | grep -v ERR_PNPM || true
./setup.sh
```

## Test Steps

### 1. TypeScript compiles

```bash
cd /Users/tyler/repos/bags/clickhouse && npx tsc --noEmit
```

**Expected:** Exit code 0, no type errors

### 2. Manifest parses through barry's bag loader

Verifies the manifest passes zod schema validation — catches field typos, missing required keys, unknown fields that `strict()` would reject.

```bash
cd /Users/tyler/repos/bags/clickhouse && npx tsx -e "
  import { parseManifest } from '@barry/bags';
  const manifest = parseManifest('/Users/tyler/repos/bags/clickhouse');
  if (!manifest) { console.log('FAIL: manifest returned null'); process.exit(1); }
  const checks = [
    ['name', manifest.name === 'clickhouse'],
    ['mcpServers.clickhouse', !!manifest.mcpServers.clickhouse],
    ['mcpServers.clickhouse.url', manifest.mcpServers.clickhouse?.url === 'https://mcp.clickhouse.cloud/mcp'],
    ['toolsEntry', !!manifest.toolsEntry],
    ['traits.clickhouse-query', !!manifest.traits['clickhouse-query']],
    ['traits.clickhouse-infra', !!manifest.traits['clickhouse-infra']],
  ];
  const failed = checks.filter(([, ok]) => !ok);
  if (failed.length) { console.log('FAIL:', failed.map(([k]) => k).join(', ')); process.exit(1); }
  console.log('OK — manifest parses with all expected fields');
" 2>&1 | grep -v DEP0205
```

**Expected:** `OK — manifest parses with all expected fields`

### 3. Bag loads via loadBag and resolves traits

Verifies the full bag loading pipeline — registry lookup, manifest parse, trait generation (auto + custom). This is the same codepath the MCP server uses to discover bag tools.

```bash
cd /Users/tyler/repos/bags/clickhouse && npx tsx -e "
  import { loadBag, getAllTraits } from '@barry/bags';
  (async () => {
    const result = loadBag('clickhouse');
    const bag = result instanceof Promise ? await result : result;
    if (!bag) { console.log('FAIL: loadBag returned null — is clickhouse registered in ~/Library/Application Support/Barry/bags.yaml?'); process.exit(1); }

    // Check auto-traits (generated from mcpServers + toolsEntry)
    const all = getAllTraits(bag);
    const traitNames = all.map(t => t.name).sort();
    const expected = ['clickhouse', 'clickhouse-infra', 'clickhouse-query', 'clickhouse-read'];
    const missing = expected.filter(e => !traitNames.includes(e));
    if (missing.length) { console.log('FAIL: missing traits:', missing.join(', ')); process.exit(1); }

    // Check MCP server resolved
    if (!bag.mcpServers.clickhouse) { console.log('FAIL: mcpServers.clickhouse not found'); process.exit(1); }

    // Check skills dir detected
    if (bag.skillsDirs.length === 0) { console.log('FAIL: no skillsDirs found'); process.exit(1); }

    console.log('OK — bag loads, ' + all.length + ' traits, ' + Object.keys(bag.mcpServers).length + ' MCP server(s), ' + bag.skillsDirs.length + ' skills dir(s)');
  })();
" 2>&1 | grep -v DEP0205
```

**Expected:** `OK — bag loads, 4 traits, 1 MCP server(s), 1 skills dir(s)`

### 4. Tools module exports all 7 tools with correct shapes

```bash
cd /Users/tyler/repos/bags/clickhouse && npx tsx -e "
  import * as tools from './src/tools.ts';
  const expected = [
    'clickhousectl_cloud_org_usage',
    'clickhousectl_cloud_service_get',
    'clickhousectl_cloud_service_list',
    'clickhousectl_local_server_list',
    'clickhousectl_local_server_start',
    'clickhousectl_local_server_stop',
    'clickhousectl_status',
  ];
  const toolList = Object.values(tools);
  const names = toolList.map(t => t.name).sort();

  // Check count
  if (toolList.length !== 7) { console.log('FAIL: expected 7 tools, got ' + toolList.length); process.exit(1); }

  // Check names match
  const missing = expected.filter(e => !names.includes(e));
  if (missing.length) { console.log('FAIL: missing tools:', missing.join(', ')); process.exit(1); }

  // Check every tool has required defineTool fields
  for (const tool of toolList) {
    const problems = [];
    if (!tool.namespace) problems.push('namespace');
    if (!tool.access) problems.push('access');
    if (!tool.name) problems.push('name');
    if (!tool.description) problems.push('description');
    if (typeof tool.handler !== 'function') problems.push('handler');
    if (problems.length) { console.log('FAIL: ' + tool.name + ' missing: ' + problems.join(', ')); process.exit(1); }
  }

  console.log('OK — 7 tools exported, all have namespace/access/name/description/handler');
" 2>&1 | grep -v DEP0205
```

**Expected:** `OK — 7 tools exported, all have namespace/access/name/description/handler`

### 5. Status tool handler returns structured result

Calls the actual `clickhousectl_status` handler — the same function the MCP server invokes. Verifies it returns `installed`, `version`, and `cloudAuth` fields.

```bash
cd /Users/tyler/repos/bags/clickhouse && npx tsx -e "
  import { clickhousectlStatus } from './src/tools.ts';
  (async () => {
    const result = await clickhousectlStatus.handler({});
    if (typeof result.installed !== 'boolean') { console.log('FAIL: installed not boolean'); process.exit(1); }
    if (!result.installed) { console.log('FAIL: clickhousectl not installed'); process.exit(1); }
    if (typeof result.version !== 'string' || !result.version.includes('clickhousectl')) {
      console.log('FAIL: unexpected version:', result.version); process.exit(1);
    }
    if (result.cloudAuth !== 'authenticated' && result.cloudAuth !== 'not authenticated') {
      console.log('FAIL: unexpected cloudAuth:', result.cloudAuth); process.exit(1);
    }
    console.log('OK — installed=' + result.installed + ', version=' + result.version + ', cloudAuth=' + result.cloudAuth);
  })();
" 2>&1 | grep -v DEP0205
```

**Expected:** `OK — installed=true, version=clickhousectl <version>, cloudAuth=authenticated`

### 6. Cloud service list handler returns data

Calls the `clickhousectl_cloud_service_list` handler end-to-end. Requires authenticated cloud access.

```bash
cd /Users/tyler/repos/bags/clickhouse && npx tsx -e "
  import { clickhousectlCloudServiceList } from './src/tools.ts';
  (async () => {
    const result = await clickhousectlCloudServiceList.handler({});
    if (typeof result.output !== 'string') { console.log('FAIL: output not string'); process.exit(1); }
    if (result.output.length < 10) { console.log('FAIL: output too short — auth issue?'); process.exit(1); }
    console.log('OK — cloud service list returned ' + result.output.length + ' chars');
  })();
" 2>&1 | grep -v DEP0205
```

**Expected:** `OK — cloud service list returned <N> chars` (N should be several thousand)

### 7. Exec helper throws ClickHouseCtlError on bad subcommand

```bash
cd /Users/tyler/repos/bags/clickhouse && npx tsx -e "
  import { runClickHouseCtl } from './src/exec.ts';
  (async () => {
    try {
      await runClickHouseCtl(['nonexistent-subcommand']);
      console.log('FAIL: should have thrown');
      process.exit(1);
    } catch (e) {
      if (e.constructor.name !== 'ClickHouseCtlError') {
        console.log('FAIL: wrong error type: ' + e.constructor.name); process.exit(1);
      }
      console.log('OK — threw ClickHouseCtlError: ' + e.message.substring(0, 80));
    }
  })();
" 2>&1 | grep -v DEP0205
```

**Expected:** `OK — threw ClickHouseCtlError: <message>`

### 8. Agent skills are linked and contain SKILL.md files

```bash
cd /Users/tyler/repos/bags/clickhouse && SKILLS=$(find -L skills/clickhouse -name SKILL.md -maxdepth 2 2>/dev/null | wc -l | tr -d ' ')
if [ "$SKILLS" -eq 0 ]; then echo "FAIL: no skills linked — run ./setup.sh"; exit 1; fi
test -f skills/clickhouse/clickhouse-best-practices/SKILL.md && echo "best-practices OK" || echo "FAIL: best-practices missing"
test -f skills/clickhouse/clickhouse-architecture-advisor/SKILL.md && echo "architecture-advisor OK" || echo "FAIL: architecture-advisor missing"
echo "$SKILLS skills linked total"
```

**Expected:** `best-practices OK`, `architecture-advisor OK`, at least 5 skills linked

### 9. ClickHouse Cloud MCP endpoint is reachable

```bash
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://mcp.clickhouse.cloud/mcp)
if [ "$HTTP_CODE" = "000" ]; then echo "FAIL: endpoint unreachable"; exit 1; fi
echo "OK — HTTP $HTTP_CODE (401 = auth required, expected for unauthenticated requests)"
```

**Expected:** `OK — HTTP 401`

## Cleanup

No cleanup needed.

## Success Criteria

- [ ] TypeScript compiles with no errors
- [ ] Manifest parses through barry's zod schema (parseManifest)
- [ ] Bag loads via loadBag, auto-traits + custom traits resolve (4 total)
- [ ] All 7 tools export with correct defineTool shape
- [ ] Status tool handler executes and returns structured {installed, version, cloudAuth}
- [ ] Cloud service list handler returns real data from ClickHouse Cloud
- [ ] Exec helper throws ClickHouseCtlError on invalid commands
- [ ] Agent skills symlinked with SKILL.md files present
- [ ] ClickHouse Cloud MCP endpoint reachable
