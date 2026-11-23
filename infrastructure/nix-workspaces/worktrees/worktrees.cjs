#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const { spawn, spawnSync } = require('node:child_process');
const mode = process.env.WORKTREE_MODE || 'fullstack';
if (!['fullstack', 'frontend'].includes(mode)) throw new Error('Invalid workspace mode.');
const frontendOnly = mode === 'frontend';
const backend = frontendOnly ? null : require('./backend.cjs');
const repos = frontendOnly ? ['frontend'] : ['frontend', 'backend'];
const apps = frontendOnly ? ['dms'] : ['dms', 'iam', 'api'];

const home = process.env.WORKTREE_HOME || process.env.HOME;
const configDir = path.join(home, '.config/nix-workspace');
const configFile = path.join(configDir, frontendOnly ? 'frontend-worktrees.json' : 'worktrees.json');
const stateDir = path.join(home, '.local/state/' + mode + '-worktrees');
const worktreesDir = path.join(home, 'worktrees');
const git = process.env.WORKTREE_GIT || '/opt/tools/bin/git';
const maxActive = 2;

function atomic(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  const tmp = file + '.' + process.pid + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 });
  fs.renameSync(tmp, file);
}

function validateName(name) {
  if (typeof name !== 'string' || !/^[a-z][a-z0-9-]{0,23}$/.test(name)) {
    throw new Error('Use a name of 1–24 lowercase letters, digits or hyphens, starting with a letter.');
  }
}

function ports(slot) {
  if (!Number.isInteger(slot) || slot < 1 || slot > 20) throw new Error('Slot must be between 1 and 20.');
  if (frontendOnly) return { dms: 4300 + slot * 10, macDms: 8200 + slot * 100 };
  if (slot === 6) throw new Error('Slot 6 is reserved for the shared API port 5800.');
  return { dms: 4200 + slot * 10, iam: 4201 + slot * 10, api: 4202 + slot * 10,
    macDms: 5200 + slot * 100, macIam: 5201 + slot * 100, macApi: 5202 + slot * 100 };
}

function readConfig() {
  if (!fs.existsSync(configFile)) return { version: 1, worktrees: [] };
  const value = JSON.parse(fs.readFileSync(configFile, 'utf8'));
  if (value.version !== 1 || !Array.isArray(value.worktrees)) throw new Error('Invalid worktree configuration.');
  const names = new Set(), slots = new Set();
  for (const entry of value.worktrees) {
    validateName(entry.name);
    ports(entry.slot);
    if (typeof entry.enabled !== 'boolean' || names.has(entry.name) || slots.has(entry.slot)) {
      throw new Error('Duplicate name/slot or invalid enabled flag.');
    }
    names.add(entry.name); slots.add(entry.slot);
  }
  if (value.worktrees.filter(x => x.enabled).length > maxActive) throw new Error('At most two worktrees may run together.');
  return value;
}

function entryRoot(entry) {
  return path.join(worktreesDir, entry.name);
}

function command(args, cwd, capture = true) {
  const result = spawnSync(args[0], args.slice(1), {
    cwd, encoding: 'utf8', stdio: capture ? ['ignore', 'pipe', 'pipe'] : ['ignore', 2, 2],
    env: { ...process.env, HUSKY: '0', SKIP_CARAUDIT_POSTINSTALL: 'true' },
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(args[0] + ' failed (' + result.status + ')' + (capture ? ': ' + result.stderr.trim() : ''));
  }
  return capture ? result.stdout.trim() : '';
}

function findEntry(config, name) {
  validateName(name);
  const entry = config.worktrees.find(x => x.name === name);
  if (!entry) throw new Error('Unknown worktree: ' + name);
  return entry;
}

async function portFree(port) {
  return new Promise(resolve => {
    const server = net.createServer();
    server.once('error', () => resolve(false));
    server.listen(port, '0.0.0.0', () => server.close(() => resolve(true)));
  });
}

function copyEnvironment(entry) {
  const source = path.join(home, 'projects/frontend-monorepo');
  const target = path.join(entryRoot(entry), 'frontend');
  const p = ports(entry.slot);
  for (const app of frontendOnly ? ['dms'] : ['dms', 'iam']) {
    for (const file of ['.env', '.env.local']) {
      const from = path.join(source, 'apps', app, file);
      const to = path.join(target, 'apps', app, file);
      if (!fs.existsSync(to) && fs.existsSync(from)) {
        fs.copyFileSync(from, to, fs.constants.COPYFILE_EXCL);
        fs.chmodSync(to, 0o600);
      }
    }
    if (frontendOnly) continue; // Retain remote API/IAM settings unchanged.
    const file = path.join(target, 'apps', app, '.env.local');
    if (fs.existsSync(file) && fs.lstatSync(file).isSymbolicLink()) throw new Error('Refusing symlinked environment file.');
    let text = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
    const updates = app === 'dms'
      ? { API_URL: 'http://localhost:' + p.macApi, BACKEND_API_URL: 'http://localhost:' + p.macApi,
          IAM_URL: 'http://localhost:' + p.macIam,
          APPSYNC_URL: 'ws://localhost:' + p.macApi + '/_notifications/wt/' + entry.name + '/graphql' }
      : { API_URL: 'http://localhost:' + p.macApi,
          DMS_WORKSPACE_URL: 'http://app.localhost:' + p.macDms + '/workspace-initialize' };
    for (const [key, value] of Object.entries(updates)) {
      const re = new RegExp('^' + key + '=.*$', 'm');
      text = re.test(text) ? text.replace(re, key + '=' + value) : text.trimEnd() + '\n' + key + '=' + value + '\n';
    }
    fs.writeFileSync(file, text, { mode: 0o600 });
    fs.chmodSync(file, 0o600);
  }
}

async function create(config, request) {
  validateName(request.name);
  const p = ports(request.slot);
  let entry = config.worktrees.find(x => x.name === request.name);
  if (entry) {
    if (entry.slot !== request.slot) throw new Error('Existing worktree has a different slot.');
  } else {
    if (config.worktrees.some(x => x.slot === request.slot)) throw new Error('Slot is already allocated.');
    for (const port of apps.map(app => p[app])) if (!await portFree(port)) throw new Error('Workspace port is occupied: ' + port);
    if (fs.existsSync(path.join(worktreesDir, request.name))) throw new Error('Destination already exists; refusing to adopt it.');
    if (backend && fs.existsSync(backend.checkout(home, request))) throw new Error('Backend worktree already exists; refusing to adopt it.');
    entry = { name: request.name, slot: request.slot, enabled: false, ...(backend ? { backendMode: backend.mode } : {}), commits: {} };
    for (const repo of repos) {
      const source = path.join(home, 'projects', repo + '-monorepo');
      const ref = request[repo + 'Ref'] || 'HEAD';
      if (typeof ref !== 'string' || !ref || ref.includes('\0')) throw new Error('Invalid Git reference.');
      entry.commits[repo] = command([git, 'rev-parse', '--verify', '--end-of-options', ref + '^{commit}'], source);
      if (command([git, 'status', '--porcelain', '--untracked-files=no'], source)) {
        process.stderr.write(repo + ': using committed ' + ref + '; uncommitted changes stay in the original checkout.\n');
      }
    }
    config.worktrees.push(entry);
    atomic(configFile, config);
  }
  const root = entryRoot(entry);
  fs.mkdirSync(root, { recursive: true, mode: 0o700 });
  for (const repo of repos) {
    const source = path.join(home, 'projects', repo + '-monorepo');
    const target = path.join(root, repo);
    const branch = 'worktree/' + entry.name;
    const gitCheck = target => {
      const expected = fs.realpathSync(path.join(source, '.git'));
      const common = command([git, 'rev-parse', '--path-format=absolute', '--git-common-dir'], target);
      if (fs.realpathSync(common) !== expected || command([git, 'branch', '--show-current'], target) !== branch) {
        throw new Error('Existing checkout does not match this worktree: ' + target);
      }
    };
    if (repo === 'backend') {
      await backend.create(home, entry, gitCheck);
    } else if (fs.existsSync(target)) {
      gitCheck(target);
    } else {
      command([git, 'worktree', 'add', '-b', branch, target, entry.commits[repo]], source, false);
    }
  }
  copyEnvironment(entry);
  return entry;
}

function status(config) {
  let runtime = null;
  try { runtime = JSON.parse(fs.readFileSync(path.join(stateDir, 'runtime.json'), 'utf8')); } catch {}
  const runnerAlive = Boolean(runtime && Date.now() - runtime.updatedAt < 15000);
  return { version: 1, mode, maxActive, runnerAlive, worktrees: config.worktrees.map(entry => ({
    ...entry, path: entryRoot(entry), ports: ports(entry.slot),
    ...(backend ? { backendPath: backend.checkout(home, entry) } : {}),
    prepared: (!backend || backend.ready(home, entry)) && fs.existsSync(path.join(entryRoot(entry), '.prepared')),
    apps: runnerAlive ? runtime.apps.filter(x => x.name === entry.name) : [],
  })) };
}

async function rpc(request) {
  fs.mkdirSync(configDir, { recursive: true, mode: 0o700 });
  if (request.action === 'list') return status(readConfig());
  const lock = path.join(configDir, frontendOnly ? 'frontend-worktrees.lock' : 'worktrees.lock');
  let fd;
  try { fd = fs.openSync(lock, 'wx', 0o600); }
  catch { throw new Error('Another worktree operation holds ' + lock + '. Check it before removing a stale lock.'); }
  fs.writeFileSync(fd, String(process.pid));
  try {
    const config = readConfig();
    if (request.action === 'create') {
      await create(config, request);
    } else {
      const entry = findEntry(config, request.name);
      const root = entryRoot(entry);
      if (request.action === 'prepare') {
        if (entry.enabled) throw new Error('Stop this worktree before installing dependencies.');
        fs.rmSync(path.join(root, '.prepared'), { force: true });
        fs.rmSync(path.join(root, '.backend-prepared'), { force: true });
        copyEnvironment(entry);
        const args = [process.env.WORKTREE_PNPM || '/opt/frontend-tools/bin/pnpm', 'install', '--frozen-lockfile'];
        if (!request.online) args.push('--offline');
        command(args, path.join(root, 'frontend'), false);
        if (backend) await backend.prepare(home, entry);
        fs.writeFileSync(path.join(root, '.prepared'), new Date().toISOString() + '\n', { mode: 0o600 });
      } else if (request.action === 'start' || request.action === 'stop') {
        if (request.action === 'start') {
          if (!(!backend || backend.ready(home, entry)) || !fs.existsSync(path.join(root, '.prepared'))) throw new Error('Run prepare before starting this worktree, and required services.');
          if (!entry.enabled && config.worktrees.filter(x => x.enabled).length >= maxActive) {
            throw new Error('Two worktrees are already running; stop one first.');
          }
          if (!entry.enabled) for (const port of apps.map(app => ports(entry.slot)[app])) {
            if (!await portFree(port)) throw new Error('Workspace port is occupied: ' + port);
          }
        }
        entry.enabled = request.action === 'start';
        atomic(configFile, config);
      } else if (request.action === 'logs') {
        if (!apps.includes(request.app)) throw new Error('App must be one of: ' + apps.join(', '));
        const file = path.join(stateDir, entry.name, request.app + '.log');
        if (!fs.existsSync(file)) return { text: 'No log yet.' };
        const fd = fs.openSync(file, 'r'), size = fs.fstatSync(fd).size;
        const buf = Buffer.alloc(Math.min(size, 32000));
        fs.readSync(fd, buf, 0, buf.length, Math.max(0, size - buf.length));
        fs.closeSync(fd);
        return { text: buf.toString().split('\n').slice(-80).join('\n') };
      } else throw new Error('Unknown action: ' + request.action);
    }
    return status(config);
  } finally {
    fs.closeSync(fd);
    fs.unlinkSync(lock);
  }
}

function terminate(child, signal = 'SIGTERM') {
  if (child.pid) try { process.kill(-child.pid, signal); } catch (error) { if (error.code !== 'ESRCH') throw error; }
}

async function supervise() {
  fs.mkdirSync(stateDir, { recursive: true, mode: 0o700 });
  const children = new Map(), retryAt = new Map();
  let stopping = false, lastError = '';
  const stop = () => {
    stopping = true;
    for (const child of children.values()) terminate(child);
    setTimeout(() => {
      for (const child of children.values()) terminate(child, 'SIGKILL');
      process.exit(0);
    }, 2000);
  };
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
  while (!stopping) {
    try {
      const config = readConfig(), desired = new Map();
      for (const entry of config.worktrees.filter(x => x.enabled)) {
        const cwd = path.join(entryRoot(entry), 'frontend');
        if (!(!backend || backend.ready(home, entry)) || !fs.existsSync(path.join(entryRoot(entry), '.prepared'))) continue;
        for (const app of apps) desired.set(entry.name + '/' + app, { entry, app, cwd });
      }
      for (const [key, child] of children) if (!desired.has(key)) {
        child.cancelled = true;
        terminate(child);
        setTimeout(() => { if (children.get(key) === child) terminate(child, 'SIGKILL'); }, 2000);
      }
      for (const [key, { entry, app, cwd }] of desired) {
        if (children.has(key) || (retryAt.get(key) || 0) > Date.now()) continue;
        const p = ports(entry.slot), port = p[app];
        if (!await portFree(port)) {
          retryAt.set(key, Date.now() + 10000);
          console.error(key + ': port ' + port + ' is occupied; leaving its owner untouched.');
          continue;
        }
        const dir = path.join(stateDir, entry.name);
        fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
        const log = path.join(dir, app + '.log');
        if (fs.existsSync(log) && fs.statSync(log).size > 5 * 1024 * 1024) fs.renameSync(log, log + '.previous');
        const fd = fs.openSync(log, 'a', 0o600);
        const env = { ...process.env, NX_DAEMON: 'false', NX_ISOLATE_PLUGINS: 'false',
          NX_WORKSPACE_DATA_DIRECTORY: '/tmp/nx-' + mode + '-worktree-' + entry.name + '-' + app,
          SERVE_TYPECHECK_CHECKERS: '2' };
        const executable = app === 'api' ? process.execPath : path.join(cwd, 'node_modules/.bin/nx');
        const args = app === 'api' ? [path.join(__dirname, 'backend-proxy.cjs'), entry.name, String(port)]
          : ['serve', app, '--host=0.0.0.0', '--port=' + port,
            '--publicHost=ws://localhost:' + (app === 'dms' ? p.macDms : p.macIam) + '/ws'];
        const child = spawn(executable, args,
          { cwd, env, detached: true, stdio: ['ignore', fd, fd] });
        fs.closeSync(fd);
        children.set(key, child);
        child.on('error', error => console.error(key + ': ' + error.message));
        child.on('close', code => {
          terminate(child);
          if (children.get(key) === child) children.delete(key);
          retryAt.set(key, Date.now() + 5000);
          console.log(key + ': exited ' + code + (child.cancelled ? ' (stopped)' : '; retrying'));
        });
        console.log(key + ': started on ' + port);
      }
      atomic(path.join(stateDir, 'runtime.json'), {
        updatedAt: Date.now(),
        apps: [...children].map(([key, child]) => {
          const [name, app] = key.split('/');
          return { name, app, pid: child.pid, stopping: Boolean(child.cancelled) };
        }),
      });
      lastError = '';
    } catch (error) {
      if (lastError !== error.message) console.error(error.message);
      lastError = error.message;
    }
    // A malformed user configuration must not take the main SSH service offline.
    fs.writeFileSync('/tmp/worktree-runner-heartbeat', String(Date.now()));
    await new Promise(resolve => setTimeout(resolve, 2000));
  }
}

if (require.main === module) {
  const action = process.argv[2];
  const task = action === 'supervise' ? supervise()
    : action === 'rpc' ? rpc(JSON.parse(Buffer.from(process.argv[3], 'base64').toString()))
      : Promise.reject(new Error('Expected supervise or rpc.'));
  task.then(value => { if (value !== undefined) console.log(JSON.stringify(value)); })
    .catch(error => { console.error(error.message); process.exitCode = 1; });
}

module.exports = { rpc, ports, readConfig, copyEnvironment };
