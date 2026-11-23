'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { spawn, spawnSync } = require('node:child_process');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'frontend-worktrees-test-'));
process.env.WORKTREE_HOME = root;
process.env.WORKTREE_MODE = 'frontend';
process.env.WORKTREE_GIT = spawnSync('which', ['git'], { encoding: 'utf8' }).stdout.trim();
const manager = require('./worktrees.cjs');
const git = (args, cwd) => {
  const r = spawnSync(process.env.WORKTREE_GIT, args, { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
};
async function until(check) {
  for (let n = 0; n < 100; n++) {
    try { if (await check()) return; } catch {}
    await new Promise(r => setTimeout(r, 200));
  }
  throw new Error('Timed out waiting for runner');
}
const get = port => new Promise((resolve, reject) => {
  const r = http.get('http://127.0.0.1:' + port, res => {
    let text = ''; res.on('data', x => { text += x; }); res.on('end', () => resolve(text));
  });
  r.on('error', reject); r.setTimeout(300, () => r.destroy());
});
test('frontend worktrees isolate code, preserve remote settings, and recover without backend services', { timeout: 60000 }, async t => {
  let daemon;
  const stop = async () => {
    if (daemon && daemon.exitCode === null) {
      const done = new Promise(r => daemon.once('exit', r)); daemon.kill('SIGTERM'); await done;
    }
  };
  t.after(async () => { await stop(); fs.rmSync(root, { recursive: true, force: true }); });
  const source = path.join(root, 'projects/frontend-monorepo');
  fs.mkdirSync(path.join(source, 'apps/dms'), { recursive: true });
  git(['init','-q'], source); git(['config','user.name','Test'], source); git(['config','user.email','test@example.invalid'], source);
  fs.writeFileSync(path.join(source, '.gitignore'), '.env*\nnode_modules/\n');
  fs.writeFileSync(path.join(source, 'apps/dms/file'), 'committed');
  fs.writeFileSync(path.join(source, 'apps/dms/.env'), 'API_URL=https://remote.example.invalid\nIAM_URL=https://iam.example.invalid\n');
  git(['add','.'], source); git(['commit','-qm','fixture'], source);
  fs.writeFileSync(path.join(source, 'apps/dms/file'), 'uncommitted');
  const pnpm = path.join(root,'pnpm'); process.env.WORKTREE_PNPM = pnpm;
  fs.writeFileSync(pnpm, '#!' + process.execPath + '\nprocess.exit(9)\n', {mode:0o755});
  for (const [name,slot] of [['alpha',6],['beta',7],['gamma',8]]) {
    const state = await manager.rpc({action:'create',name,slot});
    const e = state.worktrees.find(x => x.name === name);
    assert.equal(e.backendPath, undefined);
    assert.equal(fs.existsSync(path.join(e.path,'backend')), false);
    assert.equal(fs.readFileSync(path.join(e.path,'frontend/apps/dms/file'),'utf8'),'committed');
    assert.match(fs.readFileSync(path.join(e.path,'frontend/apps/dms/.env'),'utf8'),/API_URL=https:\/\/remote.example.invalid/);
    await assert.rejects(manager.rpc({action:'prepare',name}), /failed/);
    await assert.rejects(manager.rpc({action:'start',name}), /prepare/);
    const bin=path.join(e.path,'frontend/node_modules/.bin');fs.mkdirSync(bin,{recursive:true});
    fs.writeFileSync(path.join(bin,'nx'),'#!'+process.execPath+'\n'+
      "const fs=require('fs'),http=require('http'); const port=Number(process.argv.find(x=>x.startsWith('--port=')).split('=')[1]); http.createServer((q,r)=>r.end(fs.readFileSync('apps/dms/file'))).listen(port,'0.0.0.0');",{mode:0o755});
  }
  fs.writeFileSync(pnpm, '#!' + process.execPath + '\nprocess.exit(0)\n');
  for (const name of ['alpha','beta','gamma']) await manager.rpc({action:'prepare',name});
  const occupied=http.createServer();await new Promise(r=>occupied.listen(4360,'0.0.0.0',r));
  await assert.rejects(manager.rpc({action:'start',name:'alpha'}),/occupied/);
  await new Promise(r=>occupied.close(r));
  for (const name of ['alpha','beta']) await manager.rpc({action:'start',name});
  await assert.rejects(manager.rpc({action:'start',name:'gamma'}),/Two worktrees/);
  const launch=()=>{daemon=spawn(process.execPath,[path.join(__dirname,'worktrees.cjs'),'supervise'],{env:process.env,stdio:'ignore'});};
  launch(); await until(async()=>await get(4360)==='committed' && await get(4370)==='committed');
  fs.writeFileSync(path.join(root,'worktrees/alpha/frontend/apps/dms/file'),'alpha edit');
  assert.equal(await get(4360),'alpha edit');assert.equal(await get(4370),'committed');
  let state=await manager.rpc({action:'list'});assert.equal(state.worktrees[0].apps.length,1);
  const pid=state.worktrees[0].apps[0].pid;process.kill(pid,'SIGTERM');
  await until(async()=>{const e=(await manager.rpc({action:'list'})).worktrees[0];return e.apps[0]?.pid!==pid && await get(4360)==='alpha edit';});
  await stop();launch();await until(async()=>await get(4360)==='alpha edit' && await get(4370)==='committed');
  await manager.rpc({action:'stop',name:'alpha'});
  await until(async()=>{try{await get(4360);return false;}catch{return true;}});
  assert.equal(await get(4370),'committed');
  assert.equal(fs.readFileSync(path.join(source,'apps/dms/file'),'utf8'),'uncommitted');
  assert.equal(fs.existsSync(path.join(root,'.config/nix-workspace/worktrees.json')),false);
});
