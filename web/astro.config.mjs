// @ts-check
import { defineConfig } from 'astro/config';

// https://astro.build/config
export default defineConfig({
  site: 'https://scribe.xiangst.dev',
  output: 'static',
  build: {
    assets: '_astro',
  },
  compressHTML: true,
});
