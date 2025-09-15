---
title: 'Creating This Blog'
description: 'How to build an Astro blog with Nix flake and direnv development environment'
pubDate: 2025-09-15
tags: ['astro', 'nix', 'direnv', 'tutorial']
---

# Creating This Blog

## Prerequisites

- Nix with flakes enabled
- direnv

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

## Key Features

- **Nix flake**: Reproducible development environment
- **direnv**: Automatic environment loading
- **Custom CLI**: `blog` command for common tasks
- **Astro**: Modern static site generator
- **TypeScript**: Type safety
- **MDX support**: Enhanced markdown
- **Sitemap generation**: SEO optimization