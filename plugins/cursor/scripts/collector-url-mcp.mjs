import { chmodSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';

const pluginName = 'ev-ai-agent-hooks';

export function homeConfigPath(home = homedir()) {
  return join(home, '.ev-ai', 'config.json');
}

/** A plugin placeholder Cursor did not substitute, such as `${COLLECTOR_URL}`. */
function unsubstituted(value) {
  return value.includes('${');
}

/**
 * First real collector URL. Cursor substitutes `${COLLECTOR_URL}` in MCP args.
 * The env value is the same variable, and is ignored when it is still the placeholder.
 */
export function collectorUrlFromLaunch(env = process.env, argv = process.argv) {
  const candidates = [];
  for (const arg of argv.slice(2)) {
    if (arg.startsWith('--url=')) candidates.push(arg.slice('--url='.length));
    else if (!arg.startsWith('-')) candidates.push(arg);
  }
  if (typeof env.COLLECTOR_URL === 'string') candidates.push(env.COLLECTOR_URL);
  for (const value of candidates) {
    const trimmed = value.trim();
    if (!trimmed || unsubstituted(trimmed) || !/^https?:\/\//i.test(trimmed)) continue;
    return trimmed;
  }
  return '';
}

/**
 * Set `collector_url` to the value this process was given. Other keys, including
 * `collector_url_override`, are left as they are. A missing or unsubstituted
 * value does not replace a URL already stored.
 */
export function writeCollectorUrl(collectorUrl, home = homedir()) {
  const configPath = homeConfigPath(home);
  if (!collectorUrl || unsubstituted(collectorUrl)) return configPath;
  mkdirSync(dirname(configPath), { recursive: true });
  let current = {};
  try {
    const parsed = JSON.parse(readFileSync(configPath, 'utf8'));
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      current = parsed;
    }
  } catch {
    // Missing or unreadable config starts empty.
  }
  const next = { ...current, collector_url: collectorUrl };
  writeFileSync(configPath, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 });
  if (process.platform !== 'win32') {
    try {
      chmodSync(dirname(configPath), 0o700);
      chmodSync(configPath, 0o600);
    } catch {
      // A restrictive mode is best-effort. The file is already written.
    }
  }
  return configPath;
}

export function startCollectorUrlServer(collectorUrl) {
  const tool = {
    name: 'get_collector_url',
    description: 'Return the collector URL for the ev-ai-agent-hooks plugin.',
    inputSchema: { type: 'object', properties: {} },
  };

  function send(message) {
    process.stdout.write(`${JSON.stringify(message)}\n`);
  }

  function resultFor(method, params) {
    if (method === 'initialize') {
      return {
        protocolVersion: params?.protocolVersion ?? '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: { name: pluginName, version: '1.0.0' },
      };
    }
    if (method === 'ping') return {};
    if (method === 'tools/list') return { tools: [tool] };
    if (method === 'tools/call') {
      return { content: [{ type: 'text', text: collectorUrl }] };
    }
    if (method === 'prompts/list') return { prompts: [] };
    if (method === 'resources/list') return { resources: [] };
    if (method === 'resources/templates/list') return { resourceTemplates: [] };
    return null;
  }

  const lines = createInterface({ input: process.stdin });
  lines.on('line', (line) => {
    const raw = line.trim();
    if (!raw) return;
    let message;
    try {
      message = JSON.parse(raw);
    } catch {
      return;
    }
    if (message.id === undefined) return;
    const result = resultFor(message.method, message.params);
    if (result === null) {
      send({
        jsonrpc: '2.0',
        id: message.id,
        error: { code: -32601, message: `Method not found: ${message.method}` },
      });
      return;
    }
    send({ jsonrpc: '2.0', id: message.id, result });
  });
  lines.on('close', () => {
    process.exit(0);
  });
}

function launchedAsScript() {
  const entry = process.argv[1];
  if (!entry) return false;
  return import.meta.url === pathToFileURL(entry).href;
}

if (launchedAsScript()) {
  const collectorUrl = collectorUrlFromLaunch();
  writeCollectorUrl(collectorUrl);
  startCollectorUrlServer(collectorUrl);
}
