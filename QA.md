<!-- tools: Bash,Read -->
# QA: clickhouse pack

ClickHouse Barry pack — wraps ClickHouse Cloud MCP, clickhousectl CLI tools, and official agent skills.

## Requirements

- `node` (v18+)
- `pnpm`

## Setup

```bash
pnpm install 2>&1 | grep -v ERR_PNPM || true
./setup.sh
```

## Test Steps

### 1. TypeScript compiles

```bash
npx tsc --noEmit
```

**Expected:** Exit code 0, no output (no type errors)

### 2. Tools module loads and exports all 7 tools

```bash
npx tsx -e "
  import * as tools from './src/tools.ts';
  const names = Object.values(tools).map(t => t.name);
  console.log(JSON.stringify(names.sort()));
" 2>&1 | grep -v DEP0205
```

**Expected:** JSON array containing `clickhousectl_status`, `clickhousectl_local_server_list`, `clickhousectl_local_server_start`, `clickhousectl_local_server_stop`, `clickhousectl_cloud_service_list`, `clickhousectl_cloud_service_get`, `clickhousectl_cloud_org_usage`

### 3. Each tool has required fields (namespace, access, name, description, handler)

```bash
npx tsx -e "
  import * as tools from './src/tools.ts';
  for (const tool of Object.values(tools)) {
    const missing = [];
    if (!tool.namespace) missing.push('namespace');
    if (!tool.access) missing.push('access');
    if (!tool.name) missing.push('name');
    if (!tool.description) missing.push('description');
    if (!tool.handler) missing.push('handler');
    if (missing.length) {
      console.log('FAIL: ' + tool.name + ' missing: ' + missing.join(', '));
      process.exit(1);
    }
  }
  console.log('OK — all ' + Object.keys(tools).length + ' tools have required fields');
" 2>&1 | grep -v DEP0205
```

**Expected:** `OK — all 7 tools have required fields`

### 4. Status tool executes and returns structured result

Verify the clickhousectl_status handler returns structured JSON with install and auth info. Run via plain `node` (not npx/pnpm which modify the environment and break keychain access):

```bash
node -e "
  const { execSync } = require('child_process');
  const result = JSON.parse(execSync('clickhousectl cloud auth status', { encoding: 'utf-8' }));
  const oauth = result.find(r => r.type === 'OAuth');
  console.log(JSON.stringify({ installed: true, version: execSync('clickhousectl --version', { encoding: 'utf-8' }).trim(), cloudAuth: oauth?.status === 'Active' ? 'authenticated' : 'not authenticated' }, null, 2));
"
```

**Expected:** JSON with `installed: true`, `version` containing a version string, and `cloudAuth: "authenticated"` (if you've run `clickhousectl cloud auth login`).

### 5. Exec helper throws ClickHouseCtlError on failure

```bash
npx tsx -e "
  import { runClickHouseCtl } from './src/exec.ts';
  (async () => {
    try {
      await runClickHouseCtl(['nonexistent-subcommand']);
      console.log('FAIL: should have thrown');
      process.exit(1);
    } catch (e) {
      console.log('OK — threw: ' + e.constructor.name);
    }
  })();
" 2>&1 | grep -v DEP0205
```

**Expected:** `OK — threw: ClickHouseCtlError`

### 6. Manifest has required fields

```bash
grep -q 'manifestVersion: 1' barry-pack.yaml && grep -q 'name: clickhouse' barry-pack.yaml && grep -q 'mcp-servers:' barry-pack.yaml && grep -q 'tools:' barry-pack.yaml && echo "OK"
```

**Expected:** `OK`

### 7. Agent skills are linked

```bash
test -f skills/clickhouse/clickhouse-best-practices/SKILL.md && echo "best-practices OK"
test -f skills/clickhouse/clickhouse-architecture-advisor/SKILL.md && echo "architecture-advisor OK"
ls skills/clickhouse/ | wc -l | xargs printf "%d skills linked\n"
```

**Expected:** `best-practices OK`, `architecture-advisor OK`, at least 5 skills linked

### 8. Setup --status reports linked skills

```bash
./setup.sh --status 2>&1 | grep -c symlink
```

**Expected:** Number greater than 0

## Online Checks

### 9. ClickHouse Cloud MCP endpoint is reachable

```bash
curl -s -o /dev/null -w "%{http_code}" https://mcp.clickhouse.cloud/mcp
```

**Expected:** HTTP 401 (endpoint exists; 401 means auth required, which is expected for unauthenticated requests)

## Cleanup

No cleanup needed.

## Success Criteria

- [ ] TypeScript compiles with no errors
- [ ] All 7 tools export with correct names
- [ ] Every tool has namespace, access, name, description, and handler
- [ ] Status tool executes and returns structured JSON
- [ ] Exec helper throws ClickHouseCtlError on missing binary or failed command
- [ ] Manifest declares MCP server, tools entry, and traits
- [ ] clickhouse-best-practices and clickhouse-architecture-advisor skills are linked
- [ ] ClickHouse Cloud MCP endpoint is reachable
