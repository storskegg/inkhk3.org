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
        // Vite injects the built entry <script> into <head> wherever the source tag sits. Move it to the end
        // of <body>. Only the tag moves (plus the whitespace around it); no match or more than one fails the build.
        {
            name: 'entry-script-to-body-end',
            apply: 'build' as const,
            transformIndexHtml: {
                order: 'post' as const,
                handler(html: string) {
                    const re = /[ \t]*<script\b[^>]*\bsrc="[^"]*"[^>]*><\/script>[ \t]*\r?\n?/gi;
                    const found = html.match(re) ?? [];
                    if (found.length !== 1) {
                        throw new Error(`entry-script-to-body-end: expected exactly one <script src> in the built html, found ${found.length}`);
                    }
                    const tag = found[0].trim();
                    const rest = html.replace(re, '');
                    const close = rest.lastIndexOf('</body>');
                    if (close < 0) throw new Error('entry-script-to-body-end: no </body> in the built html');
                    return rest.slice(0, close) + '\t' + tag + '\n' + rest.slice(close);
                },
            },
        },
    ],
    root: './src',
    // '../dist' is only meant for the build output; the dev server serves from '/'.
    base: command === 'build' ? '../dist' : '/',
    publicDir: '../public',
    build: {
        outDir: '../dist',
        assetsDir: '.',
        // No modulepreload polyfill: it needs `document`, the page has no modulepreload links, and the one script
        // (credits.js) must run bare in node for test/prerender.sh.
        modulePreload: { polyfill: false },
        // Vite 8 minifies CSS with lightningcss, which rewrites grid-template-areas ".    cite  cite" to ".cite cite"
        // (an invalid area name). postcss/cssnano minify the css in `postbuild` anyway, so skip Vite's pass.
        cssMinify: false,
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
