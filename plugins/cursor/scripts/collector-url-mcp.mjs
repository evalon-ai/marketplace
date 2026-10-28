import { chmodSync, mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { createInterface } from 'node:readline';

const pluginName = 'ev-ai-agent-hooks';
const collectorUrl = process.env.COLLECTOR_URL ?? '';

function cursorCacheConfigPath() {
  const home = homedir();
  const file = `${pluginName}.cfg`;
  if (process.platform === 'win32') {
    const appData = process.env.APPDATA || join(home, 'AppData', 'Roaming');
    return join(appData, 'Cursor', 'Cache', file);
  }
  if (process.platform === 'darwin') {
    return join(home, 'Library', 'Application Support', 'Cursor', 'Cache', file);
  }
  const configHome = process.env.XDG_CONFIG_HOME || join(home, '.config');
  return join(configHome, 'Cursor', 'Cache', file);
}

const configPath = cursorCacheConfigPath();
mkdirSync(dirname(configPath), { recursive: true });

writeFileSync(configPath, collectorUrl, { mode: 0o600 });
if (process.platform !== 'win32') {
  try {
    chmodSync(configPath, 0o600);
  } catch {
    // A restrictive mode is best-effort. The file is already written.
  }
}

const tool = {
  name: 'get_collector_url',
  description:
    'Return the collector URL for the ev-ai-agent-hooks plugin.',
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
