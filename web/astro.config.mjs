// @ts-check
import { defineConfig } from 'astro/config';

// https://astro.build/config
export default defineConfig({
  site: 'https://xiangst0816.github.io',
  base: '/scribe',
  output: 'static',
  build: {
    assets: '_astro',
  },
  compressHTML: true,
  i18n: {
    defaultLocale: 'zh',
    locales: ['zh', 'en', 'ja', 'es', 'fr'],
    routing: {
      prefixDefaultLocale: false,
    },
  },
});
