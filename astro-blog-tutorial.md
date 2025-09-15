# Complete Astro Blog Setup with Nix Flake + GitHub Pages

A comprehensive tutorial to create a modern blog using Astro, with a reproducible development environment using Nix flakes and direnv, deployed to GitHub Pages.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup (Nix + Direnv)](#environment-setup-nix--direnv)
3. [Project Initialization](#project-initialization)
4. [Nix Flake Configuration](#nix-flake-configuration)
5. [Astro Blog Structure](#astro-blog-structure)
6. [Creating Content](#creating-content)
7. [GitHub Pages Deployment](#github-pages-deployment)
8. [Testing and Going Live](#testing-and-going-live)
9. [Next Steps](#next-steps)

## Prerequisites

### System Requirements
- Git
- Nix package manager
- Direnv
- GitHub account

## Install Nix
```bash
# Install Nix using the Determinate installer (recommended)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### Install Direnv
```bash
# On NixOS:
nix-env -iA nixpkgs.direnv

# On other systems with Nix:
nix profile install nixpkgs#direnv

# Or using system package manager:
# brew install direnv  # macOS
# apt install direnv   # Ubuntu/Debian
```

### Configure Direnv Shell Hook
Add the appropriate hook to your shell configuration:

```bash
# For bash (.bashrc):
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc

# For zsh (.zshrc):
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc

# For fish (config.fish):
echo 'direnv hook fish | source' >> ~/.config/fish/config.fish
```

Restart your shell or source the configuration file.

## Environment Setup (Nix + Direnv)

### 1. Create Project Directory
```bash
mkdir my-blog
cd my-blog
```

### 2. Create Nix Flake
Create `flake.nix`:

```nix
{
  description = "Astro blog development environment";

 inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Custom script for common blog tasks
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
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Node.js and package managers
            nodejs_20
            npm
            
            # Development tools
            git
            jq              # JSON processor
            curl            # HTTP client
            tree            # Directory tree viewer
            
            # Custom blog helper script
            blog-scripts
          ];

          shellHook = ''
            echo "🚀 Astro blog development environment loaded!"
            echo "Node version: $(node --version)"
            echo "NPM version: $(npm --version)"
            echo ""
            blog
            echo ""
            
            # Automatically install dependencies if node_modules doesn't exist
            if [ ! -d "node_modules" ]; then
              echo "Installing dependencies..."
              npm install
            fi
          '';

          # Environment variables
          NODE_ENV = "development";
        };
      });
}
```

### 3. Create Direnv Configuration
Create `.envrc`:

```bash
#!/usr/bin/env bash

# Use the nix flake
use flake

# Load any local environment variables
dotenv_if_exists .env.local

echo "✅ Direnv loaded successfully"
```

### 4. Initialize Nix Environment
```bash
# Allow direnv to load the environment
direnv allow

# This will build the Nix environment and install Node.js
```

## Project Initialization

### 1. Create Astro Project
```bash
# The Nix environment is now active with Node.js available
npm create astro@latest . -- --template empty --typescript

# Install additional dependencies
npm install @astrojs/mdx @astrojs/sitemap
```

### 2. Create .gitignore
Create `.gitignore`:

```gitignore
# Astro
dist/
.astro/

# Node
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*

# Environment variables
.env
.env.local
.env.production.local
.env.staging.local

# Nix
result
result-*

# Direnv
.direnv/

# OS
.DS_Store
Thumbs.db
```

## Nix Flake Configuration

### Lock the Flake
```bash
# Generate flake.lock for reproducible builds
nix flake lock
```

This creates a `flake.lock` file that pins exact versions of all dependencies.

## Astro Blog Structure

### 1. Configure Astro
Update `astro.config.mjs`:

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

### 2. Set Up Content Collections
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

### 3. Create Directory Structure
```bash
mkdir -p src/{content/blog,layouts,pages/blog}
```

### 4. Create Layout Components

#### Base Layout (`src/layouts/BaseLayout.astro`):
```astro
---
interface Props {
  title: string;
  description?: string;
}

const { title, description = "My awesome blog powered by Astro" } = Astro.props;
---

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
  <meta name="viewport" content="width=device-width" />
  <meta name="generator" content={Astro.generator} />
  <meta name="description" content={description} />
  <title>{title}</title>
</head>
<body>
  <header>
    <nav>
      <a href="/" class="logo">My Blog</a>
      <div class="nav-links">
        <a href="/">Home</a>
        <a href="/blog">Blog</a>
      </div>
    </nav>
  </header>
  <main>
    <slot />
  </main>
  <footer>
    <p>&copy; 2025 My Blog. Built with Astro.</p>
  </footer>
  
  <style>
    body {
      font-family: system-ui, -apple-system, sans-serif;
      max-width: 800px;
      margin: 0 auto;
      padding: 1rem;
      line-height: 1.6;
      color: #333;
    }
    
    header {
      border-bottom: 1px solid #eee;
      padding-bottom: 1rem;
      margin-bottom: 2rem;
    }
    
    nav {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    
    .logo {
      font-weight: bold;
      font-size: 1.2rem;
      text-decoration: none;
      color: #333;
    }
    
    .nav-links a {
      margin-left: 1rem;
      text-decoration: none;
      color: #666;
      transition: color 0.2s;
    }
    
    .nav-links a:hover {
      color: #333;
    }
    
    main {
      min-height: 70vh;
    }
    
    footer {
      border-top: 1px solid #eee;
      padding-top: 1rem;
      margin-top: 2rem;
      text-align: center;
      color: #666;
      font-size: 0.9rem;
    }
  </style>
</body>
</html>
```

#### Blog Post Layout (`src/layouts/BlogPost.astro`):
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
  article {
    max-width: 100%;
  }
  
  .post-header {
    margin-bottom: 2rem;
    padding-bottom: 1rem;
    border-bottom: 1px solid #eee;
  }
  
  h1 {
    margin-bottom: 0.5rem;
    color: #222;
  }
  
  .post-meta {
    display: flex;
    gap: 1rem;
    margin-bottom: 1rem;
  }
  
  .post-meta time,
  .post-meta .updated {
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
    color: #666;
  }
  
  .post-content {
    max-width: none;
  }
  
  /* Improve readability of markdown content */
  .post-content h2,
  .post-content h3,
  .post-content h4 {
    margin-top: 2rem;
    margin-bottom: 1rem;
  }
  
  .post-content p {
    margin-bottom: 1rem;
  }
  
  .post-content pre {
    background: #f5f5f5;
    padding: 1rem;
    border-radius: 4px;
    overflow-x: auto;
  }
  
  .post-content blockquote {
    border-left: 4px solid #ddd;
    padding-left: 1rem;
    margin: 1rem 0;
    font-style: italic;
    color: #666;
  }
</style>
```

### 5. Create Page Components

#### Home Page (`src/pages/index.astro`):
```astro
---
import BaseLayout from '../layouts/BaseLayout.astro';
import { getCollection } from 'astro:content';

const posts = await getCollection('blog');
const sortedPosts = posts
  .sort((a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf())
  .slice(0, 3); // Show only latest 3 posts on homepage
---

<BaseLayout title="Welcome to My Blog">
  <section class="hero">
    <h1>Welcome to My Blog</h1>
    <p>A modern blog built with Astro, powered by Nix, and deployed with GitHub Pages.</p>
  </section>
  
  <section class="recent-posts">
    <h2>Recent Posts</h2>
    {sortedPosts.length > 0 ? (
      <div class="posts-grid">
        {sortedPosts.map((post) => (
          <article class="post-card">
            <a href={`/blog/${post.slug}/`}>
              <h3>{post.data.title}</h3>
              <p>{post.data.description}</p>
              <time>{post.data.pubDate.toLocaleDateString()}</time>
            </a>
          </article>
        ))}
      </div>
    ) : (
      <p>No posts yet. Check back soon!</p>
    )}
    
    {sortedPosts.length > 0 && (
      <a href="/blog" class="view-all">View all posts →</a>
    )}
  </section>
</BaseLayout>

<style>
  .hero {
    text-align: center;
    margin: 3rem 0;
  }
  
  .hero h1 {
    font-size: 2.5rem;
    margin-bottom: 1rem;
    color: #222;
  }
  
  .hero p {
    font-size: 1.1rem;
    color: #666;
  }
  
  .recent-posts h2 {
    margin-bottom: 1.5rem;
    color: #333;
  }
  
  .posts-grid {
    display: grid;
    gap: 1.5rem;
    margin-bottom: 2rem;
  }
  
  .post-card {
    border: 1px solid #eee;
    padding: 1.5rem;
    border-radius: 8px;
    transition: transform 0.2s, box-shadow 0.2s;
  }
  
  .post-card:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  }
  
  .post-card a {
    text-decoration: none;
    color: inherit;
  }
  
  .post-card h3 {
    margin: 0 0 0.5rem 0;
    color: #333;
  }
  
  .post-card p {
    margin: 0 0 0.5rem 0;
    color: #666;
  }
  
  .post-card time {
    font-size: 0.9rem;
    color: #999;
  }
  
  .view-all {
    display: inline-block;
    padding: 0.5rem 1rem;
    background: #f0f0f0;
    text-decoration: none;
    border-radius: 4px;
    color: #333;
    transition: background 0.2s;
  }
  
  .view-all:hover {
    background: #e0e0e0;
  }
</style>
```

#### Blog Index (`src/pages/blog/index.astro`):
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

#### Dynamic Blog Post Page (`src/pages/blog/[...slug].astro`):
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

## Creating Content

### 1. Create Your First Blog Post
```bash
# Use the custom blog command
blog new-post "My First Blog Post"
```

Or manually create `src/content/blog/first-post.md`:

```markdown
---
title: 'My First Blog Post'
description: 'Welcome to my new blog built with Astro, Nix, and deployed on GitHub Pages!'
pubDate: 2025-01-15
tags: ['astro', 'blogging', 'nix', 'github-pages']
---

# Welcome to My Blog!

This is my first post on my new blog built with some amazing technologies:

## Tech Stack

- **Astro** - Modern static site generator
- **Nix Flakes** - Reproducible development environment  
- **GitHub Pages** - Free hosting and deployment
- **Markdown** - Simple content authoring

## What's Next?

I'm excited to share more content about:

- Web development tips and tricks
- Nix and reproducible environments
- Static site generation best practices
- Personal projects and learnings

## Code Example

Here's a simple JavaScript function:

```javascript
function greet(name) {
  return `Hello, ${name}! Welcome to my blog.`;
}

console.log(greet("World"));
```

Stay tuned for more posts!
```

### 2. Test Locally
```bash
# Start development server
blog dev
# or
npm run dev

# Visit http://localhost:4321
```

## GitHub Pages Deployment

### 1. Create GitHub Repository
1. Create a new repository on GitHub (e.g., `my-blog`)
2. **Don't** initialize with README, .gitignore, or license

### 2. Initialize Git and Push
```bash
git init
git add .
git commit -m "Initial blog setup with Nix flake"
git branch -M main
git remote add origin https://github.com/yourusername/my-blog.git
git push -u origin main
```

### 3. Create GitHub Actions Workflow
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

### 4. Enable GitHub Pages
1. Go to your repository on GitHub
2. Click **Settings** → **Pages**
3. Under **Source**, select **GitHub Actions**

### 5. Update Astro Configuration
Make sure your `astro.config.mjs` has the correct URLs:

```javascript
export default defineConfig({
  site: 'https://yourusername.github.io',  // Your GitHub username
  base: '/my-blog',  // Your repository name
  integrations: [mdx(), sitemap()],
});
```

### 6. Deploy
```bash
git add .
git commit -m "Add GitHub Actions deployment workflow"
git push
```

## Testing and Going Live

### 1. Monitor Deployment
1. Go to the **Actions** tab in your GitHub repository
2. Watch the deployment workflow complete (usually 2-3 minutes)
3. Check for any errors in the build or deploy steps

### 2. Access Your Live Blog
Visit `https://yourusername.github.io/my-blog`

### 3. Verify Everything Works
- [ ] Homepage loads correctly
- [ ] Blog index page shows your posts
- [ ] Individual blog posts are accessible
- [ ] Navigation works
- [ ] Styling is applied correctly

## Next Steps

### Content Management
```bash
# Create new posts easily
blog new-post "Advanced Astro Tips"
blog new-post "Setting Up Development Environments with Nix"

# Start development server
blog dev
```

### Customization Ideas
- Add syntax highlighting for code blocks
- Implement a search function
- Add RSS/Atom feed
- Include analytics
- Add comments system
- Create tag/category pages
- Add dark mode toggle

### Custom Domain (Optional)
1. Buy a domain from your preferred registrar
2. In your repository: **Settings** → **Pages** → **Custom domain**
3. Add your domain (e.g., `myblog.com`)
4. Configure DNS at your registrar:
   - For apex domain: A records to GitHub's IPs
   - For subdomain: CNAME to `yourusername.github.io`

### Environment Management
```bash
# Update Nix flake inputs
nix flake update

# Check what's available in your environment
nix flake show

# View dependency lock file
cat flake.lock

# Clean up Nix store
nix store gc
```

## Troubleshooting

### Common Issues

**Direnv not loading:**
```bash
# Check direnv status
direnv status

# Reload manually
direnv reload
```

**Build failures:**
```bash
# Check Node.js version
node --version  # Should be v20.x

# Clear node_modules and reinstall
rm -rf node_modules package-lock.json
npm install
```

**GitHub Pages not updating:**
- Check Actions tab for build failures
- Verify `base` URL in `astro.config.mjs`
- Ensure GitHub Pages is set to use GitHub Actions

**Nix issues:**
```bash
# Update flake
nix flake update

# Rebuild environment
direnv reload
```

## Benefits of This Setup

✅ **Reproducible Development**: Exact same environment on any machine  
✅ **Zero Configuration**: Environment loads automatically  
✅ **Modern Tooling**: Latest Astro features with excellent performance  
✅ **Free Hosting**: GitHub Pages with custom domain support  
✅ **Easy Content Creation**: Markdown with frontmatter  
✅ **Automated Deployment**: Push to deploy  
✅ **Version Controlled Environment**: Nix flake locks ensure consistency  

Your blog is now ready for content creation and is fully deployed! The combination of Astro, Nix, and GitHub Pages provides a modern, efficient, and reproducible blogging platform.
