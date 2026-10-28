import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { collectorUrlFromLaunch, homeConfigPath, writeCollectorUrl } from './collector-url-mcp.mjs';

describe('collector URL config', () => {
  it('writes collector_url and leaves collector_url_override and debug unchanged', () => {
    const home = mkdtempSync(join(tmpdir(), 'ev-ai-mcp-'));
    const configPath = homeConfigPath(home);

    writeCollectorUrl('https://hooks.example.test/first/hook', home);
    const existing = JSON.parse(readFileSync(configPath, 'utf8'));
    existing.collector_url_override = 'https://hooks.example.test/pin/hook';
    existing.debug = true;
    writeFileSync(configPath, JSON.stringify(existing));

    writeCollectorUrl('https://hooks.example.test/next/hook', home);
    const saved = JSON.parse(readFileSync(configPath, 'utf8'));
    assert.equal(saved.collector_url, 'https://hooks.example.test/next/hook');
    assert.equal(saved.collector_url_override, 'https://hooks.example.test/pin/hook');
    assert.equal(saved.debug, true);
  });

  it('keeps the stored URL when the value is empty or an unsubstituted placeholder', () => {
    const home = mkdtempSync(join(tmpdir(), 'ev-ai-mcp-'));
    writeCollectorUrl('https://hooks.example.test/keep/hook', home);
    writeCollectorUrl('${COLLECTOR_URL}', home);
    writeCollectorUrl('', home);
    const saved = JSON.parse(readFileSync(homeConfigPath(home), 'utf8'));
    assert.equal(saved.collector_url, 'https://hooks.example.test/keep/hook');
  });

  it('does not create the config when only a placeholder is given', () => {
    const home = mkdtempSync(join(tmpdir(), 'ev-ai-mcp-'));
    writeCollectorUrl('${COLLECTOR_URL}', home);
    assert.throws(() => readFileSync(homeConfigPath(home), 'utf8'), { code: 'ENOENT' });
  });
});

describe('collectorUrlFromLaunch', () => {
  const url = 'https://hooks.example.test/token/hook';

  it('reads the URL from the argument when the env value is a placeholder', () => {
    assert.equal(
      collectorUrlFromLaunch({ COLLECTOR_URL: '${COLLECTOR_URL}' }, ['node', 'mcp.mjs', url]),
      url,
    );
  });

  it('reads the URL from the env when no argument is given', () => {
    assert.equal(collectorUrlFromLaunch({ COLLECTOR_URL: url }, ['node', 'mcp.mjs']), url);
  });

  it('returns an empty string when every value is a placeholder', () => {
    assert.equal(
      collectorUrlFromLaunch({ COLLECTOR_URL: '${COLLECTOR_URL}' }, [
        'node',
        'mcp.mjs',
        '${COLLECTOR_URL}',
      ]),
      '',
    );
  });
});
