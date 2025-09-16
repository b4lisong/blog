---
title: 'Creating This Blog - Part 1'
description: 'How to build an Astro blog with Nix flake and direnv development environment'
pubDate: 2025-09-15
tags: ['astro', 'nix', 'direnv', 'tutorial']
---

A humble tutorial for my humble blog. There are many
like it, but this one is mine! I'm using Astro as
my static site generator, hosting on GitHub pages,
and setting up my build environment using Nix flakes
and `direnv`.

### Why Astro?
- I've already tried Jekyll and Hugo and itching
for something new
- I can't keep avoiding JavaScript (as much as I'd like to)
- I like *the idea* of modern front-end framework support and
reusable components
  - Let's be honest, Claude is going to do all my front-end work
 because I hate doing front-end

### Why GitHub pages?
- Mostly because it's free and it works
- Everyone else is doing it and sometimes I like
being a lemming (pls accept me)

### Why Nix flakes and `direnv`?
- I like reproducibility and declarative things
- I develop across multiple machines and want consistency
- Reduced setup friction as a result
- Totally optional, but even for a single developer, solves the "it works on my machine"
problem better than Docker, in my experience

## Prerequisites

- Nix with flakes enabled
- direnv
- A custom domain that you own for your blog

There are many ways to get the Nix package manager installed on your system, if 
you aren't already using NixOS or nix-darwin. For now, these will be beyond the
scope of this tutorial (I may write one in the future!). However, I'll include some helpful links below to get started
for those of you who don't already have a Nix environment set up:
- macOS: [https://nixcademy.com/posts/nix-on-macos/](https://nixcademy.com/posts/nix-on-macos/)
- Determinate Systems' Zero-to-Nix: [https://zero-to-nix.com/start/](https://zero-to-nix.com/start/)

## Project Setup

### Initialize Astro Project

```bash
npm create astro@latest blog
cd blog
```

Select:
- "Just the basics"
- TypeScript variant

### Create Nix Flake

Create `flake.nix`:

```nix
{
  description = "Astro blog development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};

      blog-scripts = pkgs.writeScriptBin "blog" ''
        #!/usr/bin/env bash
        case "$1" in
          "new-post")
            if [ -z "$2" ]; then
              echo "Usage: blog new-post 'Post Title'"
              exit 1
            fi
            slug=$(echo "$2" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
            date=$(date +%Y-%m-%d)
            file="src/content/blog/$slug.md"

            cat > "$file" << EOF
        ---
        title: '$2'
        description: 'Description for $2'
        pubDate: $date
        ---

        # $2

        Your content here...
        EOF
            echo "Created new post: $file"
            ;;
          "dev")
            npm run dev
            ;;
          "build")
            npm run build
            ;;
          "preview")
            npm run preview
            ;;
          *)
            echo "Available commands:"
            echo "  blog new-post 'Title'  - Create a new blog post"
            echo "  blog dev              - Start development server"
            echo "  blog build            - Build for production"
            echo "  blog preview          - Preview production build"
            ;;
        esac
      '';
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nodejs_20
          git
          jq
          curl
          tree
          blog-scripts
        ];

        shellHook = ''
          echo "🚀 Astro blog development environment loaded!"
          echo "Node version: $(node --version)"
          echo "NPM version: $(npm --version)"
          echo ""
          blog
          echo ""

          if [ ! -d "node_modules" ]; then
            echo "Installing dependencies..."
            npm install
          fi
        '';

        NODE_ENV = "development";
      };
    });
}
```

### Configure direnv

Create `.envrc`:

```bash
#!/usr/bin/env bash

use flake

dotenv_if_exists .env.local

echo "✅ Direnv loaded successfully"
```

Run:
```bash
direnv allow
```

#### Lock the Flake
```shell
# Generate flake.lock for reproducible builds
nix flake lock
```
This creates a `flake.lock` file that pins exact versions of all dependencies.

### Configure Astro

Update `astro.config.mjs`:

```javascript
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://yourdomain.com',
  integrations: [mdx(), sitemap()],
});
```

If you don't have a custom domain yet, your Astro config will look something
like this:
```javascript
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://yourusername.github.io',  // Replace with your GitHub username
  base: '/my-blog',  // Replace with your repository name
  integrations: [mdx(), sitemap()],
});
```
NOTE: if you are not using a custom domain, your routes and base path will be different 
from those shown below; adjust accordingly. Additionally, the `base` property will need to
match your GitHub repository name exactly for routing to work properly.

Install integrations:
```bash
npm install @astrojs/mdx @astrojs/sitemap
```

### Content Structure

Create `src/content/config.ts`:

```typescript
import { defineCollection, z } from 'astro:content';

const blog = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string(),
    pubDate: z.date(),
    updatedDate: z.date().optional(),
    heroImage: z.string().optional(),
    tags: z.array(z.string()).optional(),
  }),
});

export const collections = { blog };
```

### Create Layouts

Create `src/layouts/BaseLayout.astro`:

```astro
---
export interface Props {
  title: string;
  description?: string;
}

const { title, description } = Astro.props;
---

<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="description" content={description || "Blog"} />
    <meta name="viewport" content="width=device-width" />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    <meta name="generator" content={Astro.generator} />
    <title>{title}</title>
  </head>
  <body>
    <main>
      <slot />
    </main>
  </body>
</html>

<style is:global>
  html {
    font-family: system-ui, sans-serif;
  }

  body {
    margin: 0;
    padding: 2rem;
    line-height: 1.6;
  }

  main {
    max-width: 800px;
    margin: 0 auto;
  }
</style>
```

Create `src/layouts/BlogPost.astro`:

```astro
---
import BaseLayout from './BaseLayout.astro';
import type { CollectionEntry } from 'astro:content';

type Props = CollectionEntry<'blog'>['data'];

const { title, description, pubDate, updatedDate, tags } = Astro.props;
---

<BaseLayout title={title} description={description}>
  <article>
    <header class="post-header">
      <h1>{title}</h1>
      <div class="post-meta">
        <time datetime={pubDate.toISOString()}>
          {pubDate.toLocaleDateString('en-us', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
          })}
        </time>
        {updatedDate && (
          <span class="updated">
            Updated: {updatedDate.toLocaleDateString('en-us', {
              year: 'numeric',
              month: 'long',
              day: 'numeric',
            })}
          </span>
        )}
      </div>
      {tags && tags.length > 0 && (
        <div class="tags">
          {tags.map((tag) => (
            <span class="tag">{tag}</span>
          ))}
        </div>
      )}
    </header>
    <div class="post-content">
      <slot />
    </div>
  </article>
</BaseLayout>

<style>
  .post-header {
    margin-bottom: 2rem;
    padding-bottom: 1rem;
    border-bottom: 1px solid #eee;
  }

  .post-meta {
    display: flex;
    gap: 1rem;
    margin-bottom: 1rem;
    color: #666;
    font-size: 0.9rem;
  }

  .tags {
    display: flex;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .tag {
    background: #f0f0f0;
    padding: 0.2rem 0.5rem;
    border-radius: 4px;
    font-size: 0.8rem;
  }

  .post-content h2,
  .post-content h3 {
    margin-top: 2rem;
    margin-bottom: 1rem;
  }

  .post-content pre {
    background: #f5f5f5;
    padding: 1rem;
    border-radius: 4px;
    overflow-x: auto;
  }
</style>
```

### Create Pages
This blog will have a main index, separate from
the blog index, which will eventually contain
links to my various online presences, resume, etc.


Create `src/pages/index.astro`:

```astro
---
import BaseLayout from '../layouts/BaseLayout.astro';
import { getCollection } from 'astro:content';

const posts = (await getCollection('blog')).sort(
  (a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf()
);
---

<BaseLayout title="Blog">
  <h1>Blog</h1>
  <ul>
    {posts.map((post) => (
      <li>
        <a href={`/blog/${post.slug}/`}>
          <h2>{post.data.title}</h2>
          <p>{post.data.description}</p>
          <time>{post.data.pubDate.toLocaleDateString()}</time>
        </a>
      </li>
    ))}
  </ul>
</BaseLayout>
```

Create `src/pages/blog/index.astro` for the blog listing page:

```astro
---
import BaseLayout from '../../layouts/BaseLayout.astro';
import { getCollection } from 'astro:content';

const posts = await getCollection('blog');
const sortedPosts = posts.sort((a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf());
---

<BaseLayout title="All Blog Posts">
  <h1>All Blog Posts</h1>

  {sortedPosts.length > 0 ? (
    <div class="posts-list">
      {sortedPosts.map((post) => (
        <article class="post-item">
          <a href={`/blog/${post.slug}/`}>
            <h2>{post.data.title}</h2>
            <p>{post.data.description}</p>
            <div class="post-meta">
              <time>{post.data.pubDate.toLocaleDateString()}</time>
              {post.data.tags && (
                <div class="tags">
                  {post.data.tags.map((tag) => (
                    <span class="tag">{tag}</span>
                  ))}
                </div>
              )}
            </div>
          </a>
        </article>
      ))}
    </div>
  ) : (
    <p>No posts published yet.</p>
  )}
</BaseLayout>

<style>
  h1 {
    margin-bottom: 2rem;
  }

  .posts-list {
    display: flex;
    flex-direction: column;
    gap: 2rem;
  }

  .post-item {
    padding-bottom: 1.5rem;
    border-bottom: 1px solid #eee;
  }

  .post-item:last-child {
    border-bottom: none;
  }

  .post-item a {
    text-decoration: none;
    color: inherit;
    display: block;
  }

  .post-item h2 {
    margin: 0 0 0.5rem 0;
    color: #333;
    transition: color 0.2s;
  }

  .post-item:hover h2 {
    color: #666;
  }

  .post-item p {
    margin: 0 0 0.5rem 0;
    color: #666;
  }

  .post-meta {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 1rem;
  }

  .post-meta time {
    font-size: 0.9rem;
    color: #999;
  }

  .tags {
    display: flex;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .tag {
    background: #f0f0f0;
    padding: 0.2rem 0.5rem;
    border-radius: 4px;
    font-size: 0.8rem;
    color: #666;
  }
</style>
```

Create `src/pages/blog/[...slug].astro`:

```astro
---
import { type CollectionEntry, getCollection } from 'astro:content';
import BlogPost from '../../layouts/BlogPost.astro';

export async function getStaticPaths() {
  const posts = await getCollection('blog');
  return posts.map((post) => ({
    params: { slug: post.slug },
    props: post,
  }));
}

type Props = CollectionEntry<'blog'>;

const post = Astro.props;
const { Content } = await post.render();
---

<BlogPost {...post.data}>
  <Content />
</BlogPost>
```

### Create First Post

```bash
blog new-post "Hello World"
```

Edit the generated post in `src/content/blog/hello-world.md`.

### Development

Start development server:
```bash
blog dev
```

Build for production:
```bash
blog build
```

### GitHub Pages Deployment
#### 1. Create GitHub Repo
1. Create a new repository on GitHub (e.g., my-blog)
2. Don't initialize with README, .gitignore, or license
#### 2. Initialize Git and Push
```shell
git init
git add .
git commit -m "Initial blog setup with Nix flake"
git branch -M main
git remote add origin https://github.com/yourusername/my-blog.git
git push -u origin main
```
#### 3. Create GitHub Actions Workflow
Create `.github/workflows/deploy.yml`:
```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: npm
          
      - name: Install dependencies
        run: npm ci
        
      - name: Build
        run: npm run build
        
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./dist

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```
#### 4. Enable GitHub Pages
1. Go to your repository on GitHub
2. Click Settings → Pages
3. Under Source, select GitHub Actions
4. [Specify your custom domain; add A records](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site) 
#### 5. Deploy
```shell
git add .
git commit -m "Add GitHub Actions deployment workflow"
git push
```

## Testing and Going Live
### 1. Monitor Deployment
1. Go to the Actions tab in your GitHub repository
2. Watch the deployment workflow complete (usually 2-3 minutes)
3. Check for any errors in the build or deploy steps
### 2. Access Your Live Blog
Visit your custom domain URL
### 3. Verify everything works
- [ ] Homepage loads correctly
- [ ] Blog index page shows your posts
- [ ] Individual blog posts are accessible
- [ ] Navigation works between all pages
- [ ] Styling is applied correctly

## Key Features

- **Nix flake**: Reproducible development environment
- **direnv**: Automatic environment loading
- **Custom CLI**: `blog` command for common tasks
- **Astro**: Modern static site generator
- **TypeScript**: Type safety
- **MDX support**: Enhanced markdown
- **Sitemap generation**: SEO optimization

## Next Steps
You've likely noticed that the styles are quite different from what you're seeing
on my site, and that stylesheets are duplicated across different pages in this tutorial
I'll be using Tailwind CSS v4 for a more modern look-and-feel, with Claude doing most of
the heavy lifting. Stay tuned for Part 2!
