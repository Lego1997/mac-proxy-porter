#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const net = require('node:net');
const { once } = require('node:events');
const {
  createRelayService,
  parseQuickQListeners,
  parseSystemProxy,
} = require('./quickq-stable-relay');

async function createTaggedServer(tag) {
  const server = net.createServer((socket) => {
    socket.on('data', (data) => socket.write(`${tag}:${data}`));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return server;
}

async function closeServer(server) {
  await new Promise((resolve) => server.close(resolve));
}

async function roundTrip(port, value) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host: '127.0.0.1', port });
    socket.setTimeout(3000);
    socket.once('connect', () => socket.write(value));
    socket.once('data', (data) => {
      socket.destroy();
      resolve(data.toString());
    });
    socket.once('timeout', () => reject(new Error('round trip timed out')));
    socket.once('error', reject);
  });
}

async function main() {
  const proxy = parseSystemProxy(`
    HTTPEnable : 1
    HTTPPort : 10905
    HTTPSEnable : 1
    HTTPSPort : 10905
    SOCKSEnable : 1
    SOCKSPort : 10025
  `);
  assert.deepEqual(proxy, { http: 10905, https: 10905, socks: 10025 });

  const listeners = parseQuickQListeners(`
QuickQ 1 user 7u IPv4 TCP 127.0.0.1:10904 (LISTEN)
QuickQ 1 user 8u IPv4 TCP 127.0.0.1:10024 (LISTEN)
QuickQ 1 user 9u IPv4 TCP 127.0.0.1:10905 (LISTEN)
QuickQ 1 user 10u IPv4 TCP 127.0.0.1:10025 (LISTEN)
  `, proxy);
  assert.deepEqual(listeners, { http: 10905, socks: 10025 });

  const first = await createTaggedServer('first');
  const second = await createTaggedServer('second');
  let target = first.address().port;
  const relay = createRelayService({
    httpPort: 0,
    socksPort: 0,
    refreshMs: 60000,
    discover: async () => ({ http: target, socks: target }),
    log: () => {},
  });

  await relay.listen();
  const relayPort = relay.addresses().http.port;
  assert.equal(await roundTrip(relayPort, 'one'), 'first:one');

  target = second.address().port;
  await closeServer(first);
  assert.equal(await roundTrip(relayPort, 'two'), 'second:two');

  await relay.close();
  await closeServer(second);
  console.log('quickq-stable-relay tests passed');
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
