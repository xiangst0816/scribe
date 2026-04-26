# scribe-web

Marketing landing page for [Scribe](https://github.com/xiangst0816/scribe), built with [Astro](https://astro.build).

## Develop locally

```bash
cd web
npm install
npm run dev      # http://localhost:4321
```

## Production build

```bash
npm run build    # outputs to web/dist
npm run preview  # serves the built site
```

## Deployment

Deployed to **GitHub Pages** at <https://xiangst0816.github.io/scribe/> automatically by [`.github/workflows/pages.yml`](../.github/workflows/pages.yml) on every push to `main` that touches `web/**`.

### One-time setup

1. In the repo's **Settings → Pages → Build and deployment**, set **Source** to **GitHub Actions**.
2. Push to `main`. The workflow builds with [`withastro/action`](https://github.com/withastro/action) and publishes via [`actions/deploy-pages`](https://github.com/actions/deploy-pages).

That's it — no secrets, no domain, no DNS.

### Subpath caveat

Because the site is served under `/scribe/`, [`astro.config.mjs`](./astro.config.mjs) sets `base: '/scribe'`. All internal links must use `import.meta.env.BASE_URL`, e.g.:

```astro
<img src={`${import.meta.env.BASE_URL}/icon.png`} />
```

Hard-coded `/foo` paths will 404 in production.

### Switching to a custom domain later

If you buy a domain (e.g. `scribe.example.com`):

1. Add `web/public/CNAME` containing the domain.
2. In **Settings → Pages**, set the custom domain.
3. Update `site:` in [`astro.config.mjs`](./astro.config.mjs) to the new URL and **remove** `base`.
4. Revert internal links from `${import.meta.env.BASE_URL}foo` back to `/foo` (or keep them — `BASE_URL` becomes `/` and still works).

## Structure

```
web/
├── src/
│   ├── layouts/Base.astro    ← shared HTML shell, global CSS, meta tags
│   └── pages/index.astro     ← landing page (hero + features + how-it-works)
├── public/                   ← copied verbatim into the site root
│   ├── icon.png
│   ├── og-image.png
│   └── favicon.svg
├── astro.config.mjs
├── package.json
└── tsconfig.json
```
