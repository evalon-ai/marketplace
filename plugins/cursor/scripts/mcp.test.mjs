import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const mcpPath = join(dirname(fileURLToPath(import.meta.url)), '..', 'mcp.json');
const server = JSON.parse(readFileSync(mcpPath, 'utf8')).mcpServers['ev-ai-agent-hooks'];
const url = 'https://hooks.example.test/token/hook';
const placeholder = '${COLLECTOR_URL}';

const requests = [
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}',
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}',
].join('\n') + '\n';

/** Start the server exactly as Cursor does: argv straight to the command, no shell. */
function launch({ arg, env, home }) {
  const args = [...server.args.slice(0, -1), arg];
  const result = spawnSync(server.command, args, {
    input: requests,
    encoding: 'utf8',
    env: { ...process.env, HOME: home, USERPROFILE: home, COLLECTOR_URL: env },
  });
  const replies = result.stdout.trim().split('\n').filter(Boolean).map((line) => JSON.parse(line));
  return { result, replies, configPath: join(home, '.ev-ai', 'config.json') };
}

describe('plugin mcp.json', () => {
  it('does not depend on the plugin directory', () => {
    assert.equal(server.command, 'node');
    assert.ok(!JSON.stringify(server).includes('PLUGIN_ROOT'));
    assert.ok(!JSON.stringify(server).includes('workspaceFolder'));
    assert.equal(server.args.at(-1), placeholder);
    assert.equal(server.env.COLLECTOR_URL, placeholder);
  });

  it('answers the handshake and writes collector_url from the argument', () => {
    const home = mkdtempSync(join(tmpdir(), 'ev-ai-mcp-'));
    const { result, replies, configPath } = launch({ arg: url, env: placeholder, home });
    assert.equal(result.status, 0);
    assert.equal(replies[0].result.serverInfo.name, 'ev-ai-agent-hooks');
    assert.deepEqual(replies[1].result.tools, []);
    assert.equal(JSON.parse(readFileSync(configPath, 'utf8')).collector_url, url);
  });

  it('writes collector_url from the environment when the argument is a placeholder', () => {
    const home = mkdtempSync(join(tmpdir(), 'ev-ai-mcp-'));
    const { configPath } = launch({ arg: placeholder, env: url, home });
    assert.equal(JSON.parse(readFileSync(configPath, 'utf8')).collector_url, url);
  });

  it('does not create the config when only placeholders are given', () => {
    const home = mkdtempSync(join(tmpdir(), 'ev-ai-mcp-'));
    const { result, replies, configPath } = launch({ arg: placeholder, env: placeholder, home });
    assert.equal(result.status, 0);
    assert.equal(replies.length, 2);
    assert.equal(existsSync(configPath), false);
  });

  it('keeps other keys and keeps the stored URL when only placeholders are given', () => {
    const home = mkdtempSync(join(tmpdir(), 'ev-ai-mcp-'));
    mkdirSync(join(home, '.ev-ai'));
    const configPath = join(home, '.ev-ai', 'config.json');
    writeFileSync(
      configPath,
      JSON.stringify({ collector_url: 'https://hooks.example.test/old/hook', collector_url_override: 'https://hooks.example.test/pin/hook', debug: true }),
    );

    launch({ arg: placeholder, env: placeholder, home });
    assert.equal(JSON.parse(readFileSync(configPath, 'utf8')).collector_url, 'https://hooks.example.test/old/hook');

    launch({ arg: url, env: placeholder, home });
    const saved = JSON.parse(readFileSync(configPath, 'utf8'));
    assert.equal(saved.collector_url, url);
    assert.equal(saved.collector_url_override, 'https://hooks.example.test/pin/hook');
    assert.equal(saved.debug, true);
  });
});
