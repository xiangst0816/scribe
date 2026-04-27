import { ui, defaultLang, languages } from './ui';
import type { Lang, UIKey } from './ui';

export function getLangFromUrl(url: URL): Lang {
  const base = (import.meta.env.BASE_URL ?? '/').replace(/\/+$/, '');
  let path = url.pathname;
  if (base && path.startsWith(base)) path = path.slice(base.length);
  const seg = path.split('/').filter(Boolean)[0];
  if (seg && seg in languages) return seg as Lang;
  return defaultLang;
}

export function useTranslations(lang: Lang) {
  return function t(key: UIKey): string {
    return (ui[lang] as Record<string, string>)[key] ?? ui[defaultLang][key];
  };
}

export function localizePath(path: string, lang: Lang): string {
  const base = (import.meta.env.BASE_URL ?? '/').replace(/\/+$/, '');
  const clean = path.startsWith('/') ? path : `/${path}`;
  if (lang === defaultLang) return `${base}${clean}`;
  if (clean === '/') return `${base}/${lang}/`;
  return `${base}/${lang}${clean}`;
}

export const htmlLangAttr: Record<Lang, string> = {
  zh: 'zh-Hans',
  en: 'en',
  ja: 'ja',
  es: 'es',
  fr: 'fr',
};
