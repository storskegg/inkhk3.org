import type { UserConfig } from 'vite';
import cleanPlugin from 'vite-plugin-clean';

export default ({ command }: { command: 'build' | 'serve' }) => ({
    plugins: [
        // Wipe dist/ only for builds; the dev server must never touch it.
        {
            // @ts-ignore
            ...cleanPlugin({
                targetFiles: ['dist'],
            }),
            apply: 'build' as const,
        },
    ],
    root: './src',
    // '../dist' is only meant for the build output; the dev server serves from '/'.
    base: command === 'build' ? '../dist' : '/',
    publicDir: '../public',
    build: {
        outDir: '../dist',
        assetsDir: '.'
    },
    server: {
        host: '127.0.0.1',
        port: 8083,
        strictPort: true,
    },
    preview: {
        host: '127.0.0.1',
        port: 8080,
        strictPort: true,
    },
}) satisfies (env: { command: 'build' | 'serve' }) => UserConfig
