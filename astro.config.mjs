import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://b4lisong.github.io',  // Replace with your GitHub username
  base: '/blog',  // Replace with your repository name
  integrations: [mdx(), sitemap()],
});
