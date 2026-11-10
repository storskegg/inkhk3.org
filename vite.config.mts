import type { UserConfig } from 'vite';

export default () => ({
    plugins: [
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
    // Assets are root-absolute (/index-*.css, /InkHk3Serif-Bold.woff2); the site lives at the domain root.
    base: '/',
    publicDir: '../public',
    build: {
        outDir: '../dist',
        // Empty dist/ before each `vite build`. dist/ is outside the root, so Vite only does this (and stays quiet)
        // when it is set explicitly. It applies to builds only; the dev server never touches dist/.
        emptyOutDir: true,
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
}) satisfies () => UserConfig
