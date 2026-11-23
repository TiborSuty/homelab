'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');

const services = ['dms', 'admin', 'car-audit', 'adexport', 'mapper', 'mcp', 'common'];
const mode = 'unit-worktree-v1';
const source = home => path.join(home, 'projects/backend-monorepo');
const checkout = (home, entry) => path.join(source(home), '.worktrees', entry.name);

// Invoke the main checkout's tooling from the real worktree directory. Its own
// bin copies deliberately refuse host-side use; IN_DOCKER here means PHP Docker,
// not the Kubernetes workspace that hosts the Docker client.
function run(home, program, args, cwd) {
  return new Promise((resolve, reject) => {
    const child = spawn(path.join(source(home), 'bin', program), args, {
      cwd, env: { ...process.env, IN_DOCKER: '0', AI_AGENT: '1',
        PATH: path.join(source(home), 'bin') + ':' + process.env.PATH },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    for (const stream of [child.stdout, child.stderr]) {
      let pending = '';
      stream.on('data', chunk => {
        pending += chunk;
        const lines = pending.split('\n');
        pending = lines.pop();
        for (const line of lines) process.stderr.write(redact(line) + '\n');
      });
      stream.on('end', () => { if (pending) process.stderr.write(redact(pending) + '\n'); });
    }
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolve() : reject(new Error(
      program + ' ' + args.slice(0, 2).join(' ') + ' failed (' + code + '); worktree remains stopped.')));
  });
}

function redact(line) {
  // fullstack on prints local login credentials; keep them out of launcher output.
  return /(?:password|access_token|refresh_token)\s*[:=]/i.test(line) ? '[credential output omitted]' : line;
}

function verify(home, entry) {
  if (entry.backendMode !== mode) throw new Error('This older worktree has no isolated backend. Create a new named worktree; existing files are preserved.');
  const root = checkout(home, entry);
  const prefix = 'wt_' + entry.name.replaceAll('-', '_') + '_';
  for (const app of services) {
    const file = path.join(root, 'projects', app, '.env.local');
    if (!fs.existsSync(file) || fs.lstatSync(file).isSymbolicLink()) throw new Error('Backend provisioning is incomplete: ' + app);
    const text = fs.readFileSync(file, 'utf8');
    if (!text.split(/\r?\n/).includes('WORKTREE_NAME=' + entry.name)) throw new Error('Missing backend identity: ' + app);
    fs.chmodSync(file, 0o600);
  }
  for (const app of ['dms', 'car-audit']) {
    const text = fs.readFileSync(path.join(root, 'projects', app, '.env.test.local'), 'utf8');
    if (!text.split(/\r?\n/).includes('MULTITENANT_DBNAME_PREFIX=' + prefix + app.replaceAll('-', '_') + '_')) {
      throw new Error('Backend database isolation is missing: ' + app);
    }
  }
}

async function create(home, entry, gitCheck) {
  const root = checkout(home, entry);
  if (!fs.existsSync(root)) {
    await run(home, 'teas-mono', ['worktree', 'create', entry.name, '--new-branch',
      'worktree/' + entry.name, '--from', entry.commits.backend], source(home));
  }
  gitCheck(root);
  verify(home, entry);
  const alias = path.join(home, 'worktrees', entry.name, 'backend');
  if (!fs.existsSync(alias)) fs.symlinkSync(root, alias, 'dir');
  if (fs.realpathSync(alias) !== fs.realpathSync(root)) throw new Error('Backend alias points to another checkout.');
}

async function prepare(home, entry) {
  verify(home, entry);
  const root = checkout(home, entry);
  // Native create permits a failed Composer install. Reconcile strictly before
  // allowing any runtime, including when preparing a different branch later.
  await run(home, 'ai-mono', ['composer', 'install', '--no-scripts'], root);
  // This restores ONLY wt_<name>_* databases from existing local dump files.
  // Never download remote data, --restore existing data, or initialise main.
  await run(home, 'teas-mono', ['fullstack', 'on'], root);
  fs.writeFileSync(path.join(home, 'worktrees', entry.name, '.backend-prepared'), mode, { mode: 0o600 });
}

function ready(home, entry) {
  return entry.backendMode === mode && fs.existsSync(path.join(home, 'worktrees', entry.name, '.backend-prepared'));
}

module.exports = { mode, source, checkout, create, prepare, ready, verify, redact };
