import type { UserConfig } from 'vite';
import cleanPlugin from 'vite-plugin-clean';

export default {
    plugins: [
        // @ts-ignore
        cleanPlugin({
            targetFiles: ['dist'],
        }),
    ],
    root: './src',
    base: '../dist',
    publicDir: '../public',
    build: {
        outDir: '../dist',
        assetsDir: '.'
    }
} satisfies UserConfig
