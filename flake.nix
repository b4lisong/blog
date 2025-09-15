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
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          # Node.js and package managers
          nodejs_20

          # Development tools
          git
          jq # JSON processor
          curl # HTTP client
          tree # Directory tree viewer

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
