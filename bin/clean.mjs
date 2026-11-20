#!/usr/bin/env node
// Team rule: clean before every build. Removes the build output (dist/, Vite's outDir) and nothing else;
// node_modules and Vite's cache stay. Resolved from this script's location, not the cwd.
import { rmSync } from 'node:fs';
import { dirname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const target = resolve(root, 'dist');
if (!target.startsWith(root + sep) || !target.endsWith(`${sep}dist`) || target === root) {
  console.error(`clean: refusing to remove ${target} (not dist/ inside ${root})`);
  process.exit(1);
}
rmSync(target, { recursive: true, force: true });
console.log('clean: removed dist/');
