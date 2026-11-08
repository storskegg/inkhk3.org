#!/usr/bin/env node
// `npx serve` from the project root runs `npm run serve`.
import { spawnSync } from 'node:child_process';
const r = spawnSync('npm', ['run', 'serve', '--', ...process.argv.slice(2)], { stdio: 'inherit' });
process.exit(r.status ?? 1);
