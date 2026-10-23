import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
const source = await readFile(new URL('./worker.js', import.meta.url), 'utf8');
const worker = (await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)).default;
const env = {ORIGIN_URL: 'https://example.trycloudflare.com', INGRESS_TOKEN: 'x'.repeat(48)};
const req = (path, init = {}) => new Request(`https://beta.example${path}`, {
  ...init, headers: {'CF-Connecting-IP': '203.0.113.9', ...init.headers},
});

test('only public player endpoints and their exact methods are forwarded', async () => {
  globalThis.fetch = async () => { throw Error('must not forward'); };
  for (const path of ['/internal/save', '/api/release?secret=1', '/admin', '/health/']) {
    assert.equal((await worker.fetch(req(path), env)).status, 404);
  }
  assert.equal((await worker.fetch(req('/api/login'), env)).status, 404);
});

test('edge replaces spoofed forwarding credentials and strips cookies', async () => {
  globalThis.fetch = async (url, init) => {
    assert.equal(String(url), 'https://example.trycloudflare.com/api/login');
    assert.equal(init.headers.get('X-Aetheria-Ingress'), env.INGRESS_TOKEN);
    assert.equal(init.headers.get('X-Aetheria-Client-IP'), '203.0.113.9');
    assert.equal(init.headers.get('Cookie'), null);
    assert.equal(init.headers.get('X-Server-Key'), null);
    assert.equal(init.headers.get('Authorization'), 'Bearer player-token');
    assert.equal(init.redirect, 'error');
    return Response.json({ok: true}, {headers: {'Set-Cookie': 'private=1'}});
  };
  const result = await worker.fetch(req('/api/login', {method: 'POST', body: '{}', headers: {
    'X-Aetheria-Ingress': 'spoof', 'X-Aetheria-Client-IP': '127.0.0.1',
    'X-Server-Key': 'spoof', Cookie: 'private=1', Authorization: 'Bearer player-token',
  }}), env);
  assert.equal(result.status, 200);
  assert.equal(result.headers.get('Set-Cookie'), null);
  assert.equal(result.headers.get('Cache-Control'), 'no-store');
});

test('malformed or missing deployment bindings fail closed', async () => {
  for (const origin of ['garbage', 'http://origin.example', 'https://user:pass@origin.example', 'https://origin.example/private']) {
    assert.equal((await worker.fetch(req('/health'), {...env, ORIGIN_URL: origin})).status, 503);
  }
  assert.equal((await worker.fetch(req('/health'), {...env, INGRESS_TOKEN: ''})).status, 503);
});

test('undeclared oversized requests stop reading and never reach the origin', async () => {
  let cancelled = false;
  let reads = 0;
  globalThis.fetch = async () => { throw Error('must not forward'); };
  const body = new ReadableStream({
    pull(controller) { reads++; controller.enqueue(new Uint8Array(65536)); if (reads === 16) controller.close(); },
    cancel() { cancelled = true; },
  });
  const result = await worker.fetch(req('/api/login', {method: 'POST', body, duplex: 'half'}), env);
  assert.equal(result.status, 413);
  assert.equal(cancelled, true);
  assert.ok(reads <= 6, `read ${reads} chunks`);
});

test('oversized upstream responses are cancelled before buffering in full', async () => {
  let cancelled = false;
  let reads = 0;
  globalThis.fetch = async () => new Response(new ReadableStream({
    pull(controller) { reads++; controller.enqueue(new Uint8Array(32768)); if (reads === 16) controller.close(); },
    cancel() { cancelled = true; },
  }));
  const result = await worker.fetch(req('/api/release'), env);
  assert.equal(result.status, 502);
  assert.equal(cancelled, true);
  assert.ok(reads <= 4, `read ${reads} chunks`);
});
