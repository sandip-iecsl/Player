const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');

test('Microservice server starts and exposes production health & readiness endpoints', async (t) => {
  // Set testing port
  process.env.PORT = '3099';
  process.env.NODE_ENV = 'test';

  // Require server
  require('../server.js');

  // Allow server a moment to bind
  await new Promise((resolve) => setTimeout(resolve, 600));

  await t.test('GET /health returns 200 with diagnostics, metrics, and security headers', async () => {
    const res = await fetch('http://127.0.0.1:3099/health');
    assert.equal(res.status, 200);

    // Verify Helmet security headers
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('cross-origin-resource-policy'), 'cross-origin');

    const json = await res.json();
    assert.equal(json.status, 'online');
    assert.ok(json.metrics, 'Metrics object should be present');
    assert.ok(typeof json.metrics.uptimeSec === 'number');
    assert.ok(json.cache, 'Cache object should be present');
    assert.ok(typeof json.cache.extractsCached === 'number');
  });

  await t.test('GET /ready returns 200 with readiness verification', async () => {
    const res = await fetch('http://127.0.0.1:3099/ready');
    assert.equal(res.status, 200);

    const json = await res.json();
    assert.equal(json.ready, true);
    assert.ok(typeof json.activeWorkers === 'number');
  });

  await t.test('POST /api/youtube/extract returns 400 on missing URL', async () => {
    const res = await fetch('http://127.0.0.1:3099/api/youtube/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.equal(res.status, 400);
    const json = await res.json();
    assert.ok(json.error);
  });

  // Clean exit for test runner
  setImmediate(() => process.exit(0));
});
