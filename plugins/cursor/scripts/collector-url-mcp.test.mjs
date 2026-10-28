import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { homeConfigPath, writeCollectorUrl } from './collector-url-mcp.mjs';

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
});
