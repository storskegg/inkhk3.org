#!/usr/bin/env node
// `npx serve-dist` from the project root runs `npm run serve-dist`.
import { spawnSync } from 'node:child_process';
const r = spawnSync('npm', ['run', 'serve-dist', '--', ...process.argv.slice(2)], { stdio: 'inherit' });
process.exit(r.status ?? 1);
