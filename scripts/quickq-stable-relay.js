#!/usr/bin/env node
'use strict';

const net = require('node:net');
const { execFile } = require('node:child_process');

const HOST = '127.0.0.1';
const DEFAULT_HTTP_PORT = 17890;
const DEFAULT_SOCKS_PORT = 17891;
const DEFAULT_REFRESH_MS = 500;
const CONNECT_TIMEOUT_MS = 2000;

function execFileText(command, args) {
  return new Promise((resolve, reject) => {
    execFile(command, args, {
      encoding: 'utf8',
      timeout: 1500,
      maxBuffer: 256 * 1024,
    }, (error, stdout) => {
      if (error && error.code !== 1) {
        reject(error);
        return;
      }
      resolve(stdout || '');
    });
  });
}

function parseSystemProxy(output) {
  const values = {};
  for (const line of output.split('\n')) {
    const match = line.match(/^\s*([A-Za-z]+)\s*:\s*(\S+)\s*$/);
    if (match) values[match[1]] = match[2];
  }
  return {
    http: values.HTTPEnable === '1' ? Number(values.HTTPPort) || null : null,
    https: values.HTTPSEnable === '1' ? Number(values.HTTPSPort) || null : null,
    socks: values.SOCKSEnable === '1' ? Number(values.SOCKSPort) || null : null,
  };
}

function parseQuickQListeners(output, systemProxy = {}) {
  const http = [];
  const socks = [];
  for (const line of output.split('\n')) {
    const match = line.match(/127\.0\.0\.1:(\d+)\s+\(LISTEN\)/);
    if (!match) continue;
    const port = Number(match[1]);
    if (port >= 10900 && port <= 10999) http.push(port);
    if (port >= 10000 && port <= 10099) socks.push(port);
  }

  const preferredHttp = [systemProxy.http, systemProxy.https]
    .find((port) => http.includes(port));
  const preferredSocks = socks.includes(systemProxy.socks)
    ? systemProxy.socks
    : null;

  return {
    http: preferredHttp || http.at(-1) || null,
    socks: preferredSocks || socks.at(-1) || null,
  };
}

async function discoverQuickQListeners() {
  const [lsofResult, scutilResult] = await Promise.allSettled([
    execFileText('/usr/sbin/lsof', [
      '-nP', '-a', '-c', 'QuickQ',
      '-iTCP@127.0.0.1', '-sTCP:LISTEN',
    ]),
    execFileText('/usr/sbin/scutil', ['--proxy']),
  ]);

  if (lsofResult.status === 'rejected') throw lsofResult.reason;
  const systemProxy = scutilResult.status === 'fulfilled'
    ? parseSystemProxy(scutilResult.value)
    : {};
  return parseQuickQListeners(lsofResult.value, systemProxy);
}

function createRelayService(options = {}) {
  const host = options.host || HOST;
  const httpPort = options.httpPort ?? DEFAULT_HTTP_PORT;
  const socksPort = options.socksPort ?? DEFAULT_SOCKS_PORT;
  const refreshMs = options.refreshMs ?? DEFAULT_REFRESH_MS;
  const discover = options.discover || discoverQuickQListeners;
  const log = options.log || ((message) => console.log(message));

  let targets = { http: null, socks: null };
  let refreshInFlight = null;
  let refreshTimer = null;
  const openSockets = new Set();

  async function refreshTargets() {
    if (refreshInFlight) return refreshInFlight;
    refreshInFlight = (async () => {
      try {
        const next = await discover();
        if (!next || typeof next !== 'object') return targets;
        const normalized = {
          http: Number(next.http) || null,
          socks: Number(next.socks) || null,
        };
        if (normalized.http !== targets.http || normalized.socks !== targets.socks) {
          targets = normalized;
          log(`QuickQ targets: HTTP=${targets.http || 'off'} SOCKS=${targets.socks || 'off'}`);
        }
      } catch (error) {
        log(`QuickQ discovery failed; keeping last targets: ${error.message}`);
      }
      return targets;
    })().finally(() => {
      refreshInFlight = null;
    });
    return refreshInFlight;
  }

  async function openUpstream(kind, forceRefresh) {
    if (forceRefresh || !targets[kind]) await refreshTargets();
    const port = targets[kind];
    if (!port) throw new Error(`QuickQ ${kind} listener is unavailable`);

    return new Promise((resolve, reject) => {
      const upstream = net.createConnection({ host: HOST, port });
      const timer = setTimeout(() => {
        upstream.destroy(new Error(`QuickQ ${kind} connect timeout`));
      }, CONNECT_TIMEOUT_MS);

      const onError = (error) => {
        clearTimeout(timer);
        reject(error);
      };
      upstream.once('error', onError);
      upstream.once('connect', () => {
        clearTimeout(timer);
        upstream.removeListener('error', onError);
        resolve(upstream);
      });
    });
  }

  async function handleClient(kind, client) {
    openSockets.add(client);
    client.pause();
    client.setNoDelay(true);
    client.once('close', () => openSockets.delete(client));

    let upstream;
    try {
      try {
        upstream = await openUpstream(kind, !targets[kind]);
      } catch (_firstError) {
        upstream = await openUpstream(kind, true);
      }
    } catch (_error) {
      client.destroy();
      return;
    }

    openSockets.add(upstream);
    upstream.setNoDelay(true);
    upstream.once('close', () => openSockets.delete(upstream));
    client.on('error', () => upstream.destroy());
    upstream.on('error', () => client.destroy());
    client.on('close', () => upstream.destroy());
    upstream.on('close', () => client.destroy());
    client.pipe(upstream);
    upstream.pipe(client);
    client.resume();
  }

  const httpServer = net.createServer((client) => handleClient('http', client));
  const socksServer = net.createServer((client) => handleClient('socks', client));

  function listenServer(server, port) {
    return new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(port, host, () => {
        server.removeListener('error', reject);
        resolve();
      });
    });
  }

  async function listen() {
    await refreshTargets();
    await Promise.all([
      listenServer(httpServer, httpPort),
      listenServer(socksServer, socksPort),
    ]);
    refreshTimer = setInterval(refreshTargets, refreshMs);
    log(`Stable relays listening on ${host}:${httpServer.address().port} and ${host}:${socksServer.address().port}`);
  }

  async function close() {
    if (refreshTimer) clearInterval(refreshTimer);
    for (const socket of openSockets) socket.destroy();
    await Promise.all([httpServer, socksServer].map((server) => new Promise((resolve) => {
      if (!server.listening) {
        resolve();
        return;
      }
      server.close(resolve);
    })));
  }

  return {
    listen,
    close,
    refreshTargets,
    getTargets: () => ({ ...targets }),
    addresses: () => ({
      http: httpServer.address(),
      socks: socksServer.address(),
    }),
  };
}

async function main() {
  const service = createRelayService();
  await service.listen();

  let stopping = false;
  const stop = async () => {
    if (stopping) return;
    stopping = true;
    await service.close();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error.message);
    process.exit(1);
  });
}

module.exports = {
  createRelayService,
  discoverQuickQListeners,
  parseQuickQListeners,
  parseSystemProxy,
};
