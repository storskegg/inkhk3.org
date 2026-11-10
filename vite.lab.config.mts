import type { UserConfig } from 'vite';

// The font lab (lab/), served by Vite's dev server only: `npx serve` / `npm run serve`.
// It is never built or deployed: there is no build output, no plugins, no public dir.
export default {
    root: './lab',
    base: '/',
    publicDir: false,
    // Fonts, hierojax.js and the JSON data are served as they are; nothing is pre-bundled.
    optimizeDeps: { noDiscovery: true, include: [] },
    // The lab must never be built; fail loudly if someone tries.
    build: { write: false, emptyOutDir: false, outDir: '../node_modules/.vite-lab-never' },
    server: {
        host: '127.0.0.1',
        port: 8081,
        strictPort: true,
        // fonts/ is large and gitignored; do not watch it.
        watch: { ignored: ['**/lab/fonts/**', '**/*.py', '**/*.md', '**/*.tsv'] },
    },
} satisfies UserConfig;
