'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const net = require('node:net');
const { createProxy } = require('./backend-proxy.cjs');
const { redact } = require('./backend.cjs');

async function listen(server) {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return server.address().port;
}

function request(port, url, headers = {}, body = '') {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port, path: url, method: 'POST', headers }, res => {
      let text = '';
      res.on('data', part => { text += part; });
      res.on('end', () => resolve({ status: res.statusCode, text }));
    });
    req.on('error', reject); req.end(body);
  });
}

test('two API listeners pin different backend code, preserve requests, and scope notification sockets', async t => {
  const code = { 'feature-a': 'version-A', 'feature-b': 'version-B' };
  const gateway = http.createServer((req, res) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => res.end(JSON.stringify({
      code: code[req.headers['x-worktree']], workspace: req.headers['x-workspace'],
      url: req.url, body,
    })));
  });
  const apiPort = await listen(gateway);
  const notifications = http.createServer((req, res) => res.end(req.url));
  notifications.on('upgrade', (req, socket) => {
    socket.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n');
    socket.end(req.headers['x-worktree'] + ' ' + req.url);
  });
  const notificationsPort = await listen(notifications);
  const a = createProxy('feature-a', { apiPort, notificationsPort });
  const b = createProxy('feature-b', { apiPort, notificationsPort });
  const pa = await listen(a), pb = await listen(b);
  t.after(() => { a.shutdown(); b.shutdown(); gateway.close(); notifications.close(); });
  const headers = { 'x-worktree': 'feature-b', 'x-workspace': 'e2e' };
  const result = JSON.parse((await request(pa, '/dms/example?q=1', headers, 'payload')).text);
  assert.deepEqual(result, { code: 'version-A', workspace: 'e2e', url: '/dms/example?q=1', body: 'payload' });
  assert.equal(JSON.parse((await request(pb, '/dms/example')).text).code, 'version-B');
  code['feature-a'] = 'edited-A';
  assert.equal(JSON.parse((await request(pa, '/dms/example')).text).code, 'edited-A');
  assert.equal(JSON.parse((await request(pb, '/dms/example')).text).code, 'version-B');
  assert.equal((await request(pa, '/_notifications/wt/feature-b/graphql')).status, 400);
  assert.equal((await request(pa, '/_notifications/wt/feature-a/graphql')).text, '/wt/feature-a/graphql');
  const upgrade = await new Promise((resolve, reject) => {
    const socket = net.connect(pa, '127.0.0.1', () => socket.write(
      'GET /_notifications/wt/feature-a/graphql/realtime HTTP/1.1\r\nHost: localhost\r\n' +
      'Connection: Upgrade\r\nUpgrade: websocket\r\nX-Worktree: feature-b\r\n\r\n'));
    let reply = '';
    socket.on('data', data => { reply += data; });
    socket.on('end', () => resolve(reply));
    socket.on('error', reject);
  });
  assert.match(upgrade, /101 Switching Protocols/);
  assert.match(upgrade, /feature-a \/wt\/feature-a\/graphql\/realtime/);
  await new Promise(resolve => gateway.close(resolve));
  assert.equal((await request(pa, '/dms/example')).status, 502);
});

test('native fullstack credential output is omitted', () => {
  assert.equal(redact(' Password: secret-fixture'), '[credential output omitted]');
  assert.equal(redact('Data restored'), 'Data restored');
});
