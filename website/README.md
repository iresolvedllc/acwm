# acwm website

VitePress site for [wm.acw.rest](https://wm.acw.rest), deployed as a
Cloudflare Worker with static assets.

The site content is the repo itself — the project root is the VitePress
source directory, so `docs/`, `ROADMAP.md` and `UPSTREAM.md` are published
as pages without duplication. `website/home.md` is rewritten to the site
root and `public/acwm.png` is the logo.

## Local development

```bash
npm install          # once
npm run docs:dev     # http://localhost:5173
npm run docs:preview # preview the production build
```

## Deploy

```bash
npm run docs:build
wrangler deploy      # wrangler.jsonc: worker "acwm", assets .vitepress/dist,
                     # custom domain wm.acw.rest
```

The custom domain is declared in `wrangler.jsonc`
(`routes[].custom_domain`), so Cloudflare provisions the DNS record and
certificate automatically. Requires `wrangler login` with Workers + routes
permission on the `acw.rest` zone.
