import { exec } from "node:child_process";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// No TS parameter properties here — the MCP server imports bag tools under
// Node's strip-only type stripping, which can't transform that syntax.
export class ClickHouseCtlError extends Error {
  readonly exitCode: number | null;
  readonly stderr: string;

  constructor(message: string, exitCode: number | null, stderr: string) {
    super(message);
    this.name = "ClickHouseCtlError";
    this.exitCode = exitCode;
    this.stderr = stderr;
  }
}

function shellEscape(arg: string): string {
  return `'${arg.replace(/'/g, "'\\''")}'`;
}

/**
 * Find a directory containing .clickhouse/tokens.json by walking up from a
 * starting path. clickhousectl stores OAuth tokens in .clickhouse/tokens.json
 * relative to the CWD where `auth login` was run, so we need to find that
 * directory to pass as cwd when spawning the process.
 */
function findTokenDir(startDir: string): string | undefined {
  let dir = startDir;
  // Walk up at most 10 levels to avoid infinite loops on weird filesystems
  for (let i = 0; i < 10; i++) {
    if (existsSync(join(dir, ".clickhouse", "tokens.json"))) {
      return dir;
    }
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  // Also check home directory
  const home = process.env.HOME;
  if (home && existsSync(join(home, ".clickhouse", "tokens.json"))) {
    return home;
  }
  return undefined;
}

/**
 * Run a clickhousectl command and return parsed output.
 *
 * Uses exec (shell) so the subprocess inherits the user's login environment.
 * Sets cwd to a directory containing .clickhouse/tokens.json so clickhousectl
 * can find its stored OAuth token.
 *
 * Throws ClickHouseCtlError if the binary isn't found or the command fails.
 */
export function runClickHouseCtl(
  args: string[],
  options?: { timeoutMs?: number },
): Promise<string> {
  const timeoutMs = options?.timeoutMs ?? 30_000;
  const cmd = ["clickhousectl", ...args.map(shellEscape)].join(" ");

  // Find a CWD where clickhousectl can access its OAuth token
  const packDir = dirname(dirname(fileURLToPath(import.meta.url)));
  const cwd = findTokenDir(packDir) ?? process.env.HOME ?? undefined;

  return new Promise((resolve, reject) => {
    exec(cmd, { timeout: timeoutMs, cwd }, (error, stdout, stderr) => {
      if (error) {
        const msg = stderr.trim() || error.message;
        if (msg.includes("not found") || msg.includes("No such file")) {
          reject(
            new ClickHouseCtlError(
              "clickhousectl is not installed. Install it: curl https://clickhouse.com/cli | sh",
              null,
              "",
            ),
          );
          return;
        }
        reject(
          new ClickHouseCtlError(
            `clickhousectl ${args.join(" ")} failed: ${msg}`,
            error.code ?? null,
            stderr,
          ),
        );
        return;
      }
      resolve(stdout.trim());
    });
  });
}

/**
 * Check whether clickhousectl is installed and reachable on PATH.
 */
export async function isClickHouseCtlInstalled(): Promise<boolean> {
  try {
    await runClickHouseCtl(["--version"], { timeoutMs: 5_000 });
    return true;
  } catch {
    return false;
  }
}
