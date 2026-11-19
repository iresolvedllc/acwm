import { defineConfig } from 'vitepress'

// The project root is the repo root, so the existing docs tree, ROADMAP and
// UPSTREAM are site pages without duplication (default srcDir '.').
// website/home.md is rewritten to the site root; the logo is served from
// public/acwm.png.
export default defineConfig({
  title: 'acwm',
  description:
    'A fast, practical Wayland compositor with a built-in status bar, native secrets and its own greeter.',
  lang: 'en-US',
  cleanUrls: true,
  srcExclude: [
    '**/node_modules/**',
    '.github/**',
    'README.md', // GitHub face; the site home is website/home.md
    'website/README.md',
    'website/node_modules/**',
    'docs/patches/**',
    '.zig-cache/**',
    'zig-out/**',
    'build/**',
    'result/**',
  ],
  rewrites: {
    'website/home.md': 'index.md',
  },
  head: [
    ['link', { rel: 'icon', href: '/acwm.png' }],
    ['meta', { name: 'theme-color', content: '#101014' }],
  ],
  themeConfig: {
    logo: '/acwm.png',
    nav: [
      { text: 'Guide', link: '/docs/', activeMatch: '/docs/' },
      { text: 'Roadmap', link: '/ROADMAP' },
      { text: 'Upstream', link: '/UPSTREAM' },
      { text: 'GitHub', link: 'https://github.com/iresolvedllc/acwm' },
    ],
    sidebar: {
      '/docs/': [
        {
          text: 'Getting started',
          items: [
            { text: 'Introduction', link: '/docs/' },
            { text: 'Installation', link: '/docs/installation' },
            { text: 'Quick start', link: '/docs/quick-start' },
          ],
        },
        {
          text: 'Configuration',
          items: [
            { text: 'Basics', link: '/docs/configuration/basics' },
            { text: 'Input', link: '/docs/configuration/input' },
            { text: 'Monitors', link: '/docs/configuration/monitors' },
            { text: 'TOML', link: '/docs/configuration/toml' },
            { text: 'Miscellaneous', link: '/docs/configuration/miscellaneous' },
            { text: 'Secrets (oo7)', link: '/docs/configuration/secrets' },
            { text: 'Greeter (greetd)', link: '/docs/configuration/greetd' },
            { text: 'XDG portals', link: '/docs/configuration/xdg-portals' },
          ],
        },
        {
          text: 'Bindings',
          items: [
            { text: 'Keys', link: '/docs/bindings/keys' },
            { text: 'Mouse & gestures', link: '/docs/bindings/mouse-gestures' },
          ],
        },
        {
          text: 'Window management',
          items: [
            { text: 'Overview', link: '/docs/window-management/overview' },
            { text: 'Layouts', link: '/docs/window-management/layouts' },
            { text: 'Rules', link: '/docs/window-management/rules' },
            { text: 'Scratchpad', link: '/docs/window-management/scratchpad' },
          ],
        },
        {
          text: 'Visuals',
          items: [
            { text: 'Animations', link: '/docs/visuals/animations' },
            { text: 'Effects', link: '/docs/visuals/effects' },
            { text: 'Status bar', link: '/docs/visuals/status-bar' },
            { text: 'Theming', link: '/docs/visuals/theming' },
          ],
        },
        {
          text: 'More',
          items: [
            { text: 'IPC', link: '/docs/ipc' },
            { text: 'Nix options', link: '/docs/nix-options' },
            { text: 'Screenshots', link: '/docs/screenshot' },
            { text: 'FAQ', link: '/docs/faq' },
          ],
        },
      ],
    },
    search: { provider: 'local' },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/iresolvedllc/acwm' },
    ],
    footer: {
      message: 'GPL-3.0 · derivative work of mangowc (see UPSTREAM.md)',
      copyright: 'Copyright © iResolved, LLC.',
    },
    outline: { level: [2, 3] },
  },
})
