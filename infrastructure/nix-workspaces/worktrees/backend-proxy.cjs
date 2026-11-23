'use strict';

const http = require('node:http');
const net = require('node:net');

// A fixed worktree per listener also covers IAM, downloads and requests whose
// browser localStorage still contains another worktree name. Never fall back to main.
function createProxy(name, { apiPort = 8080, notificationsPort = 8091 } = {}) {
  if (!/^[a-z][a-z0-9-]{0,23}$/.test(name)) throw new Error('Invalid worktree name.');
  const sockets = new Set();
  function target(req) {
    const notifications = req.url.startsWith('/_notifications/');
    const url = notifications ? req.url.slice('/_notifications'.length) : req.url;
    if (!url.startsWith('/') || url.startsWith('//')) throw new Error('Invalid request target.');
    if (notifications && !url.startsWith('/wt/' + name + '/graphql')) throw new Error('Invalid notification scope.');
    return { port: notifications ? notificationsPort : apiPort, path: url,
      headers: { ...req.headers, 'x-worktree': name } };
  }
  const server = http.createServer((req, res) => {
    let route;
    try { route = target(req); } catch { res.writeHead(400); res.end(); return; }
    const upstream = http.request({ hostname: '127.0.0.1', ...route, method: req.method }, reply => {
      res.writeHead(reply.statusCode, reply.headers);
      reply.pipe(res);
    });
    upstream.on('error', () => {
      if (!res.headersSent) res.writeHead(502, { 'Content-Type': 'text/plain' });
      res.end('Worktree backend unavailable.\n');
    });
    req.on('aborted', () => upstream.destroy());
    res.on('close', () => upstream.destroy());
    req.pipe(upstream);
  });
  server.on('connection', socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
  });
  server.on('upgrade', (req, socket, head) => {
    let route;
    try { route = target(req); } catch { socket.end('HTTP/1.1 400 Bad Request\r\n\r\n'); return; }
    const upstream = net.connect(route.port, '127.0.0.1', () => {
      const headers = Object.entries(route.headers).map(([key, value]) => key + ': ' + value).join('\r\n');
      upstream.write(req.method + ' ' + route.path + ' HTTP/1.1\r\n' + headers + '\r\n\r\n');
      if (head.length) upstream.write(head);
      socket.pipe(upstream).pipe(socket);
    });
    upstream.on('error', () => socket.destroy());
    socket.on('error', () => upstream.destroy());
    socket.on('close', () => upstream.destroy());
  });
  server.shutdown = () => { server.close(); for (const socket of sockets) socket.destroy(); };
  return server;
}

if (require.main === module) {
  const port = Number(process.argv[3]);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid port.');
  const server = createProxy(process.argv[2]);
  server.listen(port, '127.0.0.1', () => console.log('Backend proxy listening on ' + port));
  process.on('SIGTERM', () => server.shutdown());
  process.on('SIGINT', () => server.shutdown());
}

module.exports = { createProxy };
