'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { spawn, spawnSync } = require('node:child_process');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'fullstack-worktrees-test-'));
process.env.WORKTREE_HOME = root;
process.env.WORKTREE_GIT = spawnSync('which', ['git'], { encoding: 'utf8' }).stdout.trim();
const manager = require('./worktrees.cjs');
let daemon;

function git(args, cwd) {
  const result = spawnSync(process.env.WORKTREE_GIT, args, { cwd, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

async function until(check, description, timeout = 20000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    try { const value = await check(); if (value) return value; } catch {}
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  throw new Error('Timed out: ' + description);
}

function get(port) {
  return new Promise((resolve, reject) => {
    const req = http.get('http://127.0.0.1:' + port, response => {
      let data = '';
      response.on('data', part => { data += part; });
      response.on('end', () => resolve(data));
    });
    req.on('error', reject);
    req.setTimeout(500, () => req.destroy(new Error('timeout')));
  });
}

function launchDaemon() {
  daemon = spawn(process.execPath, [path.join(__dirname, 'worktrees.cjs'), 'supervise'], {
    env: process.env, stdio: 'ignore',
  });
  return daemon;
}

async function stopDaemon() {
  if (daemon && daemon.exitCode === null) {
    const exited = new Promise(resolve => daemon.once('exit', resolve));
    daemon.kill('SIGTERM');
    await exited;
  }
}

test('worktree creation preserves source edits; supervisor recovers and stops only its own servers',
  { timeout: 60000 }, async t => {
    t.after(async () => { await stopDaemon(); fs.rmSync(root, { recursive: true, force: true }); });
    for (const repo of ['frontend', 'backend']) {
      const cwd = path.join(root, 'projects', repo + '-monorepo');
      fs.mkdirSync(cwd, { recursive: true });
      git(['init', '-q'], cwd);
      git(['config', 'user.email', 'test@example.invalid'], cwd);
      git(['config', 'user.name', 'Test'], cwd);
      fs.writeFileSync(path.join(cwd, 'README'), 'committed\n');
      fs.writeFileSync(path.join(cwd, '.gitignore'), '.env*\nnode_modules/\n');
      if (repo === 'backend') {
        fs.appendFileSync(path.join(cwd, '.gitignore'), '.worktrees/\n');
        fs.mkdirSync(path.join(cwd, 'bin'));
        const native = '#!' + process.execPath + '\n' + String.raw`
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const main = path.dirname(__dirname), args = process.argv.slice(2);
if (process.env.IN_DOCKER !== '0') process.exit(31);
if (args[0] === 'worktree' && args[1] === 'create') {
  const name = args[2], dest = path.join(main, '.worktrees', name);
  const result = cp.spawnSync(process.env.WORKTREE_GIT,
    ['worktree','add','-b',args[4],dest,args[6]], {cwd:main,stdio:'ignore'});
  if (result.status) process.exit(result.status);
  for (const app of ['dms','admin','car-audit','adexport','mapper','mcp','common']) {
    const dir = path.join(dest,'projects',app); fs.mkdirSync(dir,{recursive:true});
    fs.writeFileSync(path.join(dir,'.env.local'),'WORKTREE_NAME='+name+'\n');
    fs.writeFileSync(path.join(dir,'.env.test.local'),
      'MULTITENANT_DBNAME_PREFIX=wt_'+name.replaceAll('-','_')+'_'+app.replaceAll('-','_')+'_\n');
  }
} else if (args[0] === 'fullstack' && args[1] === 'on') {
  if (!process.cwd().startsWith(path.join(main,'.worktrees')+path.sep)) process.exit(32);
  if (fs.existsSync('.fail-provision')) process.exit(36);
  fs.writeFileSync(path.join(process.cwd(),'.fullstack-called'), 'scoped');
} else process.exit(33);
`;
        fs.writeFileSync(path.join(cwd, 'bin/teas-mono'), native, { mode: 0o755 });
        fs.writeFileSync(path.join(cwd, 'bin/ai-mono'), '#!' + process.execPath + '\n' + String.raw`
const fs=require('node:fs');
if (process.argv.slice(2).join(' ')!=='composer install --no-scripts') process.exit(34);
if (fs.existsSync('.fail-install')) process.exit(35);
`, { mode: 0o755 });
      }
      if (repo === 'frontend') for (const app of ['dms', 'iam']) {
        const dir = path.join(cwd, 'apps', app);
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, '.keep'), '');
        fs.writeFileSync(path.join(dir, '.env'), 'TEST_VALUE=private-fixture\n');
        fs.writeFileSync(path.join(dir, '.env.local'), 'API_URL=http://localhost:5800\nIAM_URL=http://localhost:5201\n');
      }
      git(['add', '.'], cwd);
      git(['commit', '-qm', 'fixture'], cwd);
      fs.appendFileSync(path.join(cwd, 'README'), 'uncommitted\n');
    }
    await assert.rejects(manager.rpc({ action: 'create', name: '../bad', slot: 19 }));
    await assert.rejects(manager.rpc({ action: 'create', name: 'reserved', slot: 6 }), /reserved/);
    const state = await manager.rpc({ action: 'create', name: 'fixture', slot: 19 });
    const entry = state.worktrees[0], p = entry.ports;
    assert.equal(entry.enabled, false);
    assert.equal(fs.readFileSync(path.join(entry.path, 'frontend/README'), 'utf8'), 'committed\n');
    assert.match(fs.readFileSync(path.join(root, 'projects/frontend-monorepo/README'), 'utf8'), /uncommitted/);
    const environment = path.join(entry.path, 'frontend/apps/dms/.env.local');
    assert.match(fs.readFileSync(environment, 'utf8'), /IAM_URL=http:\/\/localhost:7101/);
    assert.match(fs.readFileSync(environment, 'utf8'), /API_URL=http:\/\/localhost:7102/);
    assert.match(fs.readFileSync(environment, 'utf8'), /APPSYNC_URL=ws:\/\/localhost:7102\/_notifications\/wt\/fixture\/graphql/);
    assert.equal(fs.realpathSync(path.join(entry.path, 'backend')), fs.realpathSync(entry.backendPath));
    assert.equal(fs.statSync(environment).mode & 0o777, 0o600);
    await assert.rejects(manager.rpc({ action: 'create', name: 'duplicate', slot: 19 }), /allocated/);
    await assert.rejects(manager.rpc({ action: 'start', name: 'fixture' }), /prepare/);
    const bin = path.join(entry.path, 'frontend/node_modules/.bin');
    fs.mkdirSync(bin, { recursive: true });
    fs.writeFileSync(path.join(bin, 'nx'), '#!' + process.execPath + '\n' +
      "const http=require('node:http');\n" +
      "const port=Number(process.argv.find(x=>x.startsWith('--port=')).split('=')[1]);\n" +
      "http.createServer((req,res)=>res.end(process.env.NX_WORKSPACE_DATA_DIRECTORY)).listen(port,'0.0.0.0');\n",
      { mode: 0o755 });
    const pnpm = path.join(root, 'pnpm');
    fs.writeFileSync(pnpm, '#!' + process.execPath + '\nprocess.exit(0);\n', { mode: 0o755 });
    process.env.WORKTREE_PNPM = pnpm;
    fs.writeFileSync(path.join(entry.backendPath, '.fail-install'), '');
    await assert.rejects(manager.rpc({ action: 'prepare', name: 'fixture' }), /failed/);
    await assert.rejects(manager.rpc({ action: 'start', name: 'fixture' }), /prepare/);
    fs.unlinkSync(path.join(entry.backendPath, '.fail-install'));
    fs.writeFileSync(path.join(entry.backendPath, '.fail-provision'), '');
    await assert.rejects(manager.rpc({ action: 'prepare', name: 'fixture' }), /failed/);
    await assert.rejects(manager.rpc({ action: 'start', name: 'fixture' }), /prepare/);
    fs.unlinkSync(path.join(entry.backendPath, '.fail-provision'));
    await manager.rpc({ action: 'prepare', name: 'fixture' });
    assert.equal(fs.readFileSync(path.join(entry.backendPath, '.fullstack-called'), 'utf8'), 'scoped');
    const occupied = http.createServer();
    await new Promise(resolve => occupied.listen(p.dms, '0.0.0.0', resolve));
    await assert.rejects(manager.rpc({ action: 'start', name: 'fixture' }), /occupied/);
    await new Promise(resolve => occupied.close(resolve));
    await manager.rpc({ action: 'start', name: 'fixture' });
    launchDaemon();
    assert.match(await until(() => get(p.dms), 'DMS started'), /fixture-dms/);
    assert.match(await until(() => get(p.iam), 'IAM started'), /fixture-iam/);
    assert.match(await until(() => get(p.api), 'API proxy started'), /Worktree backend unavailable/);
    const firstPid = (await manager.rpc({ action: 'list' })).worktrees[0].apps.find(x => x.app === 'dms').pid;
    process.kill(firstPid, 'SIGTERM');
    await until(async () => {
      const current = (await manager.rpc({ action: 'list' })).worktrees[0].apps.find(x => x.app === 'dms');
      return current && current.pid !== firstPid && await get(p.dms);
    }, 'DMS recovered after exit');
    await stopDaemon();
    launchDaemon();
    assert.match(await until(() => get(p.dms), 'enabled worktree restored after runner restart'), /fixture-dms/);
    await manager.rpc({ action: 'stop', name: 'fixture' });
    await until(async () => {
      try { await get(p.dms); return false; } catch { return true; }
    }, 'DMS stopped');
    await until(async () => {
      try { await get(p.api); return false; } catch { return true; }
    }, 'API proxy stopped');
    assert.ok(fs.existsSync(path.join(entry.path, 'frontend/README')));
    assert.ok(fs.existsSync(path.join(entry.path, 'backend/README')));
  });
