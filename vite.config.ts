import type { UserConfig } from 'vite'

export default {
    root: './src',
    base: '../dist',
    publicDir: '../public',
    build: {
        outDir: '../dist',
        assetsDir: '.'
    }
} satisfies UserConfig
