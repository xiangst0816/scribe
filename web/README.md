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

Deployed to **Cloudflare Pages** automatically by [`.github/workflows/deploy-web.yml`](../.github/workflows/deploy-web.yml) on every push to `main` that touches `web/**`.

### One-time Cloudflare setup

1. **Create a Pages project**

   In the [Cloudflare Pages dashboard](https://dash.cloudflare.com/?to=/:account/pages), click **Create a project → Direct upload**, name it `scribe`, and skip the file-upload step (the GitHub Action will populate it on first deploy). You can also let the GitHub Action create the project automatically by simply running once.

2. **Get an API token**

   In **My Profile → API Tokens**, click **Create Token** with the **"Edit Cloudflare Workers"** template, or build a custom token with these permissions:
   - Account · Cloudflare Pages · **Edit**
   - User · User Details · **Read**

3. **Get your Account ID**

   Visible in the Cloudflare dashboard right sidebar (any zone or the Workers / Pages overview).

4. **Add secrets to GitHub**

   In `xiangst0816/scribe` → **Settings → Secrets and variables → Actions → New repository secret**:

   | Name | Value |
   |---|---|
   | `CLOUDFLARE_API_TOKEN` | the token from step 2 |
   | `CLOUDFLARE_ACCOUNT_ID` | the account ID from step 3 |

5. **Push and watch**

   Any push to `main` that changes `web/**` triggers the workflow, builds the site, and uploads to CF Pages. The first deployment creates the project if missing.

### Custom domain

Once deployed, in the Pages project go to **Custom domains → Set up a custom domain**, add `scribe.xiangst.dev` (or whatever), and CF will guide you through the DNS step. Update `site:` in [`astro.config.mjs`](./astro.config.mjs) to match.

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
