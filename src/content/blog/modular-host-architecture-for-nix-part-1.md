---
title: 'Modular host architecture for Nix - Part 1'
description: 'Transforming a monolithic flake.nix into a sophisticated architecture-based organization'
pubDate: 2025-09-16
---

## Overview
[ryan4yin's nix-config](https://github.com/ryan4yin/nix-config) is an absolute masterpiece.

It's how I've learned Nix; starting with a more [basic config](https://github.com/ryan4yin/nix-config/tree/i3-kickstarter),
incrementally adding more advanced and sophisticated features. 

This writeup series will assume a basic familiarity with Nix and flakes.
For a refresher, or for those new to Nix and/or flakes, check out 
[ryan4yin's great beginner guide](https://nixos-and-flakes.thiscute.world)!

One of my favorite aspects of ryan4yin's design is how they implement host configurations;
it's modular and composable, organized around architecture. It's a [fine-grained](https://github.com/ryan4yin/nix-config/tree/main/outputs)
approach which really shines when the number of machines grows large, and the burden
of management and maintenance starts to increase.

**Key Benefits:**
- **Automatic host discovery** - No need to manually add each host to `flake.nix`
- **Architecture-based organization** - Clear separation by system type
- **Scalable structure** - Easy to add new hosts without touching core files
- **Testing integration** - Built-in eval tests and NixOS tests
- **Composable modules** - Flexible module combinations per host

Neither of us would recommend it for a small number of machines, but if you are currently
(or anticipate being) burdened by a typical, hard-coded, monolothic flake like I am,
read on!

## The Problem
My current `flake.nix` hardcodes every host configuration:

### Current Architecture (My nix-config)

```
flake.nix                           # Manual host definitions
├── darwinConfigurations.a2251      # Manually listed in flake
├── darwinConfigurations.sksm3      # Manually listed in flake
├── nixosConfigurations.rpi4b       # Manually listed in flake
├── nixosConfigurations.x1c4g       # Manually listed in flake
└── nixosConfigurations.nixvm       # Manually listed in flake

hosts/                              # Individual host directories
├── a2251/
│   ├── system.nix                  # Host system config
│   └── home.nix                    # Host home manager config
├── sksm3/
├── rpi4b/
├── x1c4g/
└── nixvm/

variables/default.nix               # Centralized host metadata
└── hosts = {
    a2251 = { hostname = "a2251"; system = "x86_64-darwin"; };
    sksm3 = { hostname = "sksm3"; system = "aarch64-darwin"; };
    # ... etc
}

lib/modules.nix                     # Simple helper functions
```

### Current approach - flake.nix
```nix
...
darwinConfigurations.${vars.hosts.a2251.hostname} =
  nix-darwin.lib.darwinSystem (mkDarwinHost vars.hosts.a2251.hostname);

darwinConfigurations.${vars.hosts.sksm3.hostname} =
  nix-darwin.lib.darwinSystem (mkDarwinHost vars.hosts.sksm3.hostname);

nixosConfigurations.${vars.hosts.rpi4b.hostname} =
  nixpkgs.lib.nixosSystem (mkNixOSHost vars.hosts.rpi4b.hostname);

nixosConfigurations.${vars.hosts.x1c4g.hostname} =
  nixpkgs.lib.nixosSystem (mkNixOSHost vars.hosts.x1c4g.hostname);

nixosConfigurations.${vars.hosts.nixvm.hostname} =
  nixpkgs.lib.nixosSystem (mkNixOSHost vars.hosts.nixvm.hostname);

...
```
**Problems with Current Approach:**
1. **Manual flake maintenance** - Each new host requires editing `flake.nix`
2. **No architecture separation** - Mixed system types in same namespace
3. **No testing framework** - No eval tests or automated validation

As the number of systems grows, this can get unwieldy, particularly if I also
want to maintain multiple variants of a given system (for example, different window
managers, VM vs bare metal, etc.). I want to maintain fewer files when adding a new host, not
have to touch the main `flake.nix` every time, and build a foundation for better 
automated testing.

### The Solution: Architecture-Based Separation

ryan4yin's approach separates by target architecture, creating clear boundaries:

```
flake.nix                           # References outputs/default.nix
└── outputs = inputs: import ./outputs inputs;

outputs/                            # Architecture-based organization
├── default.nix                     # Merges all architectures
├── x86_64-linux/
│   ├── default.nix                 # Auto-discovers src/ hosts
│   ├── src/                        # Individual host files
│   │   ├── host1.nix               # Single host definition
│   │   ├── host2.nix               # Single host definition
│   │   └── ...
│   └── tests/                      # Eval tests for this arch
├── aarch64-linux/
│   ├── default.nix
│   ├── src/
│   └── tests/
└── aarch64-darwin/
    ├── default.nix
    ├── src/
    └── tests/

hosts/                              # Individual host directories
├── darwin-hostname1/               # Prefixed by platform
│   ├── default.nix                 # System config
│   └── home.nix                    # Home manager config
├── linux-hostname1/
└── ...

lib/                                # Rich helper functions
├── default.nix                     # Entry point
├── macosSystem.nix                 # Darwin system builder
├── nixosSystem.nix                 # NixOS system builder
└── ...
```

**Benefits of Target Approach:**
1. **Auto-discovery** - Adding a host = creating a single `.nix` file
2. **Architecture separation** - Clear boundaries between system types
3. **Scalable testing** - Per-architecture eval tests
4. **Rich helpers** - Comprehensive system builders
5. **No central registry** - No need to edit `flake.nix` for new hosts

### Under the Hood: Haumea
https://github.com/nix-community/haumea is a Nix library that provides automatic filesystem-based module discovery and loading. It scans directories and automatically imports
  .nix files, making them available without manual imports.

#### What Haumea Does

##### Core Functionality

**Haumea scans a directory and loads all .nix files**
  data = haumea.lib.load {
    src = ./src;           # Directory to scan
    inputs = args;         # Arguments passed to each file
  };
**Result: { "file1" = <file1.nix output>; "file2" = <file2.nix output>; }**

  In Our Architecture

  1. Scans outputs/{arch}/src/ directories
  2. Imports each .nix file automatically
  3. Passes common arguments (inputs, lib, myvars, etc.) to each file
  4. Collects outputs from each file into a single attribute set
  5. Merges configurations using lib.attrsets.mergeAttrsList

  Benefits to Our Architecture

  ✅ Automatic Discovery

  - Before: Manual host listing in flake.nix
  - After: Drop file in outputs/{arch}/src/ → automatically available

  ✅ Scalability

  - ryan4yin manages 20+ hosts effortlessly with this pattern

  ✅ Architecture Separation

  - Clear boundaries: ARM64/x86_64, Darwin/Linux
  - Prevents accidental cross-architecture contamination

  ✅ Reduced Maintenance

  - No more forgetting to add hosts to flake.nix
  - No more merge conflicts in central configuration files

  Trade-offs

  Benefits vs. Drawbacks

  | With Haumea                | Without Haumea                             |
  |----------------------------|--------------------------------------------|
  | ✅ Automatic discovery     | ❌ (More) Manual registry maintenance      |
  | ✅ No central bottleneck   | ✅ Explicit host listing                   |
  | ✅ Scales to many hosts    | ❌ Gets unwieldy with many hosts           |
  | ✅ Architecture separation | ❌ Mixed architectures in one place        |
  | ❌ Less explicit           | ✅ Crystal clear what hosts exist          |
  | ❌ Additional dependency   | ✅ No extra dependencies                   |

  Key Trade-off: Explicitness vs. Automation

  Without Haumea (explicit):
  **flake.nix - you see exactly what hosts exist**
```nix
  darwinConfigurations = {
    a2251 = darwinSystem (mkHost "a2251");
    sksm3 = darwinSystem (mkHost "sksm3");
    newhost = darwinSystem (mkHost "newhost");  # Must add manually
  };
```
  With Haumea (automatic):
  **Hosts discovered automatically from filesystem**
  **You must look at outputs/{arch}/src/ to see what exists**
```nix
  darwinConfigurations = lib.mergeAttrsList (
    map (it: it.darwinConfigurations or {}) autoDiscoveredHosts
  );
```

  When Haumea Makes Sense

  ✅ Good fit:
  - Many hosts
  - Frequent host additions
  - Team environments (reduces merge conflicts)
  - Standardized host patterns

  ❌ Less beneficial:
  - Few hosts (2-3 hosts)
  - Stable host count
  - Solo environments
  - Preference for explicit configuration

  Our Context

  For our nix-config, Haumea provides significant benefits:
  - Multiple architectures (separation is valuable)
  - Growing configuration (likely to add more hosts)
  - Learning opportunity (gaining experience with modern Nix patterns)

  The trade-off of less explicitness is worth the gains in maintainability and scalability, especially as the configuration grows.

## Detailed Code Analysis

### ryan4yin's Core Components

#### 1. Main Outputs Controller (`outputs/default.nix`)

```nix
{
  self,
  nixpkgs,
  pre-commit-hooks,
  ...
}@inputs:
let
  inherit (inputs.nixpkgs) lib;
  mylib = import ../lib { inherit lib; };
  myvars = import ../vars { inherit lib; };

  # Helper to generate specialArgs per system
  genSpecialArgs = system: inputs // {
    inherit mylib myvars;
    pkgs-unstable = import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
    pkgs-stable = import inputs.nixpkgs-stable {
      inherit system;
      config.allowUnfree = true;
    };
  };

  # Architecture-based system modules
  nixosSystems = {
    x86_64-linux = import ./x86_64-linux (args // { system = "x86_64-linux"; });
    aarch64-linux = import ./aarch64-linux (args // { system = "aarch64-linux"; });
  };
  darwinSystems = {
    aarch64-darwin = import ./aarch64-darwin (args // { system = "aarch64-darwin"; });
  };
```

**Key Features:**
- **Architecture separation** - Each system type has its own module
- **Shared arguments** - Common args passed to all architectures
- **Multiple nixpkgs** - Stable, unstable, and patched versions available
- **Composition pattern** - All systems merged into final outputs

#### 2. Architecture-Specific Discovery (`outputs/aarch64-darwin/default.nix`)

```nix
{
  lib,
  inputs,
  ...
}@args:
let
  inherit (inputs) haumea;

  # Auto-discover all host files in src/
  data = haumea.lib.load {
    src = ./src;
    inputs = args;
  };
  dataWithoutPaths = builtins.attrValues data;

  # Merge all discovered hosts
  outputs = {
    darwinConfigurations = lib.attrsets.mergeAttrsList (
      map (it: it.darwinConfigurations or { }) dataWithoutPaths
    );
    packages = lib.attrsets.mergeAttrsList (map (it: it.packages or { }) dataWithoutPaths);
  };
```

**Key Features:**
- **Haumea integration** - Automatic file discovery and loading
- **No manual imports** - Files in `src/` are automatically processed
- **Flexible structure** - Each file can export different output types
- **Composable results** - All outputs merged into architecture-level results

#### 3. Individual Host Definition (`outputs/aarch64-darwin/src/fern.nix`)

```nix
{
  inputs,
  lib,
  mylib,
  myvars,
  system,
  genSpecialArgs,
  ...
}@args:
let
  name = "fern";

  modules = {
    darwin-modules = (map mylib.relativeToRoot [
      "secrets/darwin.nix"
      "modules/darwin"
      "hosts/darwin-${name}"  # Platform-prefixed host dir
    ]) ++ [
      {
        modules.desktop.fonts.enable = true;
      }
    ];

    home-modules = map mylib.relativeToRoot [
      "hosts/darwin-${name}/home.nix"
      "home/darwin"
    ];
  };

  systemArgs = modules // args;
in
{
  # Export configuration for this host
  darwinConfigurations.${name} = mylib.macosSystem systemArgs;
}
```

**Key Features:**
- **Single-host focus** - Each file defines one host
- **Platform prefixing** - Host directories prefixed with platform type
- **Helper functions** - Uses `mylib.macosSystem` for consistency
- **Module composition** - Flexible combination of system and home modules

#### 4. Rich Helper Functions (`lib/macosSystem.nix`)

```nix
{
  lib,
  inputs,
  darwin-modules,
  home-modules ? [ ],
  myvars,
  system,
  genSpecialArgs,
  specialArgs ? (genSpecialArgs system),
  ...
}:
let
  inherit (inputs) nixpkgs-darwin home-manager nix-darwin;
in
nix-darwin.lib.darwinSystem {
  inherit system specialArgs;
  modules = darwin-modules ++ [
    ({ lib, ... }: {
      nixpkgs.pkgs = import nixpkgs-darwin {
        inherit system;
        config.allowUnfree = true;
      };
    })
  ] ++ (lib.optionals ((lib.lists.length home-modules) > 0) [
    home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "home-manager.backup";
      home-manager.extraSpecialArgs = specialArgs;
      home-manager.users."${myvars.username}".imports = home-modules;
    }
  ]);
}
```

**Key Features:**
- **Consistent system building** - Standardized approach across all hosts
- **Optional home manager** - Can be included or excluded per host
- **Flexible specialArgs** - Custom arguments passed to all modules
- **Platform-specific nixpkgs** - Uses appropriate package set per platform

## Migration Plan

### Phase 1: Dependencies and Infrastructure

#### Step 1.1: Add Haumea Input

**File: `flake.nix`**
```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";
  nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
  home-manager.url = "github:nix-community/home-manager/release-25.05";

  # Add haumea for automatic module discovery
  haumea.url = "github:nix-community/haumea/v0.2.2";
  haumea.inputs.nixpkgs.follows = "nixpkgs";
};
```

#### Step 1.2: Enhanced Library Functions

**Critical Note**: We match ryan4yin's library structure exactly for consistency with the proven architecture. 
The `relativeToRoot` function is essential for the entire system to work.

**File: `lib/default.nix`**
```nix
{ lib, ... }:
{
  # System builders for creating configurations
  macosSystem = import ./macosSystem.nix;
  nixosSystem = import ./nixosSystem.nix;

  # Attribute manipulation utilities
  attrs = import ./attrs.nix { inherit lib; };

  # Use path relative to the root of the project (ryan4yin's implementation)
  relativeToRoot = lib.path.append ../.;

  # Path scanning utility 
  scanPaths = path:
    builtins.map (f: (path + "/${f}")) (
      builtins.attrNames (
        lib.attrsets.filterAttrs (
          path: _type:
          (_type == "directory")
          || ((path != "default.nix") && (lib.strings.hasSuffix ".nix" path))
        ) (builtins.readDir path)
      )
    );
}
```

**File: `lib/attrs.nix`** (required for mergeAttrsList)
```nix
# Attribute set manipulation utilities used throughout the configuration
{ lib, ... }:
{
  # These are used by outputs/default.nix to merge host configurations
  inherit (lib.attrsets) mapAttrs mapAttrs' mergeAttrsList foldlAttrs;

  # Additional helper for list to attrs conversion
  listToAttrs = lib.genAttrs;
}

**File: `lib/macosSystem.nix`**
```nix
{
  lib,
  inputs,
  darwin-modules,
  home-modules ? [],
  myvars,  # Our variables, not ryan4yin's
  system,
  genSpecialArgs,
  specialArgs ? (genSpecialArgs system),
  ...
}: let
  inherit (inputs) nixpkgs home-manager nix-darwin;
in
  nix-darwin.lib.darwinSystem {
    inherit system specialArgs;
    modules =
      darwin-modules
      ++ [
        (_: {
          nixpkgs.pkgs = import nixpkgs {
            inherit system;
            # Enable unfree packages
            config.allowUnfree = true;
          };
        })
      ]
      # Check if we have any home modules;
      # if true: include the modules
      # if false: include nothing
      # Home Manager only activated if we actually have
      # home configuration
      ++ (lib.optionals ((lib.lists.length home-modules) > 0) [
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            # Use system nixpkgs
            useGlobalPkgs = true;
            # Install to user profile
            useUserPackages = true;
            # Backup conflicts
            backupFileExtension = "home-manager.backup";
            # Pass our variables to HM
            extraSpecialArgs = specialArgs;
            # User config
            users."${myvars.user.username}".imports = home-modules;
          };
        }
      ]);
  }
```

**File: `lib/nixosSystem.nix`**
```nix
{
  inputs,
  lib,
  system,
  genSpecialArgs,
  nixos-modules,
  home-modules ? [],
  specialArgs ? (genSpecialArgs system),
  myvars,
  ...
}: let
  inherit (inputs) nixpkgs home-manager;
in
  nixpkgs.lib.nixosSystem {
    inherit system specialArgs;
    modules =
      nixos-modules
      ++ [
        (_: {
          nixpkgs.pkgs = import nixpkgs {
            inherit system;
            # Enable unfree packages
            config.allowUnfree = true;
          };
        })
      ]
      # Check if we have any home modules;
      # if true: include the modules
      # if false: include nothing
      # Home Manager only activated if we actually have
      # home configuration
      ++ (lib.optionals ((lib.lists.length home-modules) > 0) [
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            # Use system nixpkgs
            useGlobalPkgs = true;
            # Install to user profile
            useUserPackages = true;
            # Backup conflicts
            backupFileExtension = "home-manager.backup";
            # Pass our variables to HM
            extraSpecialArgs = specialArgs;
            # User config
            users."${myvars.user.username}".imports = home-modules;
          };
        }
      ]);
  }
```

#### Step 1.3: Create Outputs Directory Structure

```bash
mkdir -p outputs/x86_64-darwin/src
mkdir -p outputs/x86_64-darwin/tests
mkdir -p outputs/aarch64-darwin/src
mkdir -p outputs/aarch64-darwin/tests
mkdir -p outputs/x86_64-linux/src
mkdir -p outputs/x86_64-linux/tests
mkdir -p outputs/aarch64-linux/src
mkdir -p outputs/aarch64-linux/tests
```

### Phase 2: Core Infrastructure

#### Step 2.1: Main Outputs Controller

**CRITICAL**: This file is the heart of the new architecture. 
It must also correctly import our `variables` (`myvars`) and pass them through the system.

**File: `outputs/default.nix`** (new)
```nix
{
  self,
  nixpkgs,
  nixpkgs-unstable,
  nix-darwin,
  home-manager,
  haumea,  # Don't forget to add haumea to inputs
  ...
}@inputs:
let
  inherit (inputs.nixpkgs) lib;
  mylib = import ../lib { inherit lib; };
  myvars = import ../variables;  # OUR variables, not ../vars

  # Generate specialArgs for each system
  genSpecialArgs = system: inputs // {
    inherit mylib myvars;
    pkgs-unstable = import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
  };

  # Common args for all architectures
  args = {
    inherit inputs lib mylib myvars genSpecialArgs;
  };

  # Architecture-specific modules
  nixosSystems = {
    x86_64-linux = import ./x86_64-linux (args // { system = "x86_64-linux"; });
    aarch64-linux = import ./aarch64-linux (args // { system = "aarch64-linux"; });
  };
  darwinSystems = {
    x86_64-darwin = import ./x86_64-darwin (args // { system = "x86_64-darwin"; });
    aarch64-darwin = import ./aarch64-darwin (args // { system = "aarch64-darwin"; });
  };

  allSystems = nixosSystems // darwinSystems;
  allSystemNames = builtins.attrNames allSystems;
  nixosSystemValues = builtins.attrValues nixosSystems;
  darwinSystemValues = builtins.attrValues darwinSystems;
  allSystemValues = nixosSystemValues ++ darwinSystemValues;

  # Helper for generating attributes across all systems
  forAllSystems = func: (nixpkgs.lib.genAttrs allSystemNames func);
in
{
  # NixOS Configurations
  nixosConfigurations = lib.attrsets.mergeAttrsList (
    map (it: it.nixosConfigurations or { }) nixosSystemValues
  );

  # macOS Configurations
  darwinConfigurations = lib.attrsets.mergeAttrsList (
    map (it: it.darwinConfigurations or { }) darwinSystemValues
  );

  # Packages
  packages = forAllSystems (system: allSystems.${system}.packages or { });

  # Development Shells
  devShells = forAllSystems (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          alejandra
          pre-commit
          statix
          deadnix
          nix-tree
          manix
          nil
          jq
          git
          lua-language-server
          stylua
          selene
        ];
      };
    });

  # Formatter
  formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
}
```

#### Step 2.2: Architecture-Specific Controllers

**IMPORTANT**: These controllers use haumea to auto-discover host files. 
The `haumea.lib.load` function automatically imports all `.nix` files in the `src/` directory and passes the `args` to each file.

**File: `outputs/aarch64-darwin/default.nix`**
```nix
{
  lib,
  inputs,
  ...
}@args:
let
  inherit (inputs) haumea;

  # Auto-discover all host files in src/
  # Each file in src/ will be imported and passed 'args'
  data = haumea.lib.load {
    src = ./src;
    inputs = args;
  };
  # Remove the file paths, keeping only the values
  dataWithoutPaths = builtins.attrValues data;

  # Merge all discovered hosts into a single attrset
  outputs = {
    darwinConfigurations = lib.attrsets.mergeAttrsList (
      map (it: it.darwinConfigurations or { }) dataWithoutPaths
    );
    packages = lib.attrsets.mergeAttrsList (map (it: it.packages or { }) dataWithoutPaths);
  };
in
outputs // {
  inherit data; # for debugging - allows inspecting what haumea loaded

  # Add eval tests support (optional, can be added later)
  evalTests = haumea.lib.loadEvalTests {
    src = ./tests;
    inputs = args // { inherit outputs; };
  };
}
```

**File: `outputs/x86_64-darwin/default.nix`**
```nix
# Same as aarch64-darwin/default.nix
```

**File: `outputs/x86_64-linux/default.nix`**
```nix
{
  lib,
  inputs,
  ...
}@args:
let
  inherit (inputs) haumea;

  data = haumea.lib.load {
    src = ./src;
    inputs = args;
  };
  dataWithoutPaths = builtins.attrValues data;

  outputs = {
    nixosConfigurations = lib.attrsets.mergeAttrsList (
      map (it: it.nixosConfigurations or { }) dataWithoutPaths
    );
    packages = lib.attrsets.mergeAttrsList (map (it: it.packages or { }) dataWithoutPaths);
  };
in
outputs // {
  inherit data;
}
```

**File: `outputs/aarch64-linux/default.nix`**
```nix
# Same as x86_64-linux/default.nix
```

### Phase 3: Host Migration

#### Step 3.1: Rename Host Directories

**WARNING**: This step breaks the current configuration temporarily. Do this only after Phase 1 and 2 are complete.

```bash
# Add platform prefixes to existing host directories
# This preserves git history
git mv hosts/a2251 hosts/darwin-a2251
git mv hosts/sksm3 hosts/darwin-sksm3
git mv hosts/rpi4b hosts/linux-rpi4b
git mv hosts/x1c4g hosts/linux-x1c4g
git mv hosts/nixvm hosts/linux-nixvm

# Also rename system.nix to default.nix in each host directory
mv hosts/darwin-a2251/system.nix hosts/darwin-a2251/default.nix
mv hosts/darwin-sksm3/system.nix hosts/darwin-sksm3/default.nix
mv hosts/linux-rpi4b/system.nix hosts/linux-rpi4b/default.nix
mv hosts/linux-x1c4g/system.nix hosts/linux-x1c4g/default.nix
mv hosts/linux-nixvm/system.nix hosts/linux-nixvm/default.nix
```

#### Step 3.2: Create Host Definition Files

**File: `outputs/x86_64-darwin/src/a2251.nix`**
```nix
{
  inputs,
  lib,
  mylib,
  myvars,
  system,
  genSpecialArgs,
  ...
}@args:
let
  name = "a2251";

  modules = {
    darwin-modules = (map mylib.relativeToRoot [
      "modules/base.nix"
      "modules/darwin"
      "hosts/darwin-${name}"
    ]) ++ [
      {
        # Host-specific system module config can go here
        nixpkgs.hostPlatform = system;
        system.primaryUser = myvars.user.username;
      }
    ];

    home-modules = map mylib.relativeToRoot [
      "hosts/darwin-${name}/home.nix"
    ];
  };

  systemArgs = modules // args;
in
{
  darwinConfigurations.${name} = mylib.macosSystem systemArgs;
}
```

**File: `outputs/aarch64-darwin/src/sksm3.nix`**
```nix
{
  inputs,
  lib,
  mylib,
  myvars,
  system,
  genSpecialArgs,
  ...
}@args:
let
  name = "sksm3";

  modules = {
    darwin-modules = (map mylib.relativeToRoot [
      "modules/base.nix"
      "modules/darwin"
      "hosts/darwin-${name}"
    ]) ++ [
      {
        nixpkgs.hostPlatform = system;
        system.primaryUser = myvars.user.username;
      }
    ];

    home-modules = map mylib.relativeToRoot [
      "hosts/darwin-${name}/home.nix"
    ];
  };

  systemArgs = modules // args;
in
{
  darwinConfigurations.${name} = mylib.macosSystem systemArgs;
}
```

**File: `outputs/aarch64-linux/src/rpi4b.nix`**
```nix
{
  inputs,
  lib,
  mylib,
  myvars,
  system,
  genSpecialArgs,
  ...
}@args:
let
  name = "rpi4b";

  modules = {
    nixos-modules = (map mylib.relativeToRoot [
      "modules/base.nix"
      "modules/nixos"
      "hosts/linux-${name}"
    ]) ++ [
      {
        nixpkgs.hostPlatform = system;
      }
    ];

    home-modules = map mylib.relativeToRoot [
      "hosts/linux-${name}/home.nix"
    ];
  };

  systemArgs = modules // args;
in
{
  nixosConfigurations.${name} = mylib.nixosSystem systemArgs;
}
```

#### Step 3.3: Update Host Directory Structure

**File: `hosts/darwin-a2251/default.nix`** (modified from current system.nix)
```nix
# IMPORTANT: This file no longer needs to import base.nix or modules/darwin
# Those are handled in the outputs/ host definition
# Also no longer needs to import variables - passed as myvars
{myvars, ...}: {
  # Host-specific system configuration
  # No need to set nixpkgs.hostPlatform here - handled in outputs/
  # No need to set system.primaryUser here - handled in outputs/

  system = {
    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToEscape = true;
    };
  };

  # Environment and host-specific settings
  environment.variables = {
    EDITOR = myvars.preferences.editor;
  };

  # User configuration - same as before
  users.users.${myvars.user.username} = {
    home = "/Users/${myvars.user.username}";
    shell = pkgs.${myvars.user.shell};
  };

  # Homebrew packages specific to this host
  homebrew.casks = [
    "steam"
    # ... other host-specific apps
  ];
}
```

### Phase 4: Flake Integration

#### Step 4.1: Update Main Flake

**File: `flake.nix`** (simplified)
```nix
{
  description = "Modular nix{-darwin,OS} config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    haumea.url = "github:nix-community/haumea/v0.2.2";
    haumea.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: import ./outputs inputs;
}
```

### Phase 5: Testing and Validation

#### Step 5.1: Basic Eval Tests

**File: `outputs/x86_64-darwin/tests/hostnames/expr.nix`** (new)
```nix
{ outputs, ... }:
let
  hostnames = builtins.attrNames outputs.darwinConfigurations;
in
{
  a2251-exists = builtins.elem "a2251" hostnames;
}
```

**File: `outputs/x86_64-darwin/tests/hostnames/expected.nix`** (new)
```nix
{
  a2251-exists = true;
}
```

## Validation Steps

### Phase-by-Phase Validation

After each phase, validate the configuration still works:

#### After Phase 1 (Dependencies):
```bash
# Check flake still evaluates
nix flake metadata
nix flake check --no-build
```

#### After Phase 2 (Infrastructure):
```bash
# Test the new outputs structure
nix eval .#debugAttrs --show-trace
```

#### After Phase 3 (Host Migration):
```bash
# Test specific host configurations
nix eval .#darwinConfigurations.a2251.config.system.build.toplevel --show-trace
nix eval .#nixosConfigurations.rpi4b.config.system.build.toplevel --show-trace
```

#### After Phase 4 (Integration):
**NOTE: I'm using just recipes to make this process easier. My justfile contains: ***
```
just check

  Auto-detects platform and runs appropriate check command:

  On macOS (Darwin):
  sudo darwin-rebuild check --flake .#<hostname>

  On Linux (NixOS):
  sudo nixos-rebuild dry-build --flake .#<hostname>

  What it does: Validates the configuration and shows what would be built without actually building or switching to it.

  just build

  Auto-detects platform and runs appropriate build command:

  On macOS (Darwin):
  darwin-rebuild build --flake .#<hostname>

  On Linux (NixOS):
  nixos-rebuild build --flake .#<hostname>

  What it does: Builds the system configuration but doesn't switch to it. Useful for testing that everything compiles correctly.

  just rebuild

  Auto-detects platform and runs appropriate rebuild command:

  On macOS (Darwin):
  sudo darwin-rebuild switch --flake .#<hostname>

  On Linux (NixOS):
  sudo nixos-rebuild switch --flake .#<hostname>

  What it does: Builds the configuration and switches the system to use it immediately.
```
```bash
# Full system test
nix flake check
just check

# Try building without switching
just build

# If all passes, switch
just rebuild
```

### Common Issues and Fixes

1. **"attribute 'mergeAttrsList' missing"**
   - Ensure you're using nixpkgs 23.11 or later
   - Or implement fallback in lib/attrs.nix

2. **"cannot find flake 'flake:haumea'"**
   - Ensure haumea is properly added to inputs
   - Check `haumea.inputs.nixpkgs.follows = "nixpkgs"`

3. **"undefined variable 'myvars'"**
   - Check outputs/default.nix imports ../variables correctly
   - Verify genSpecialArgs includes myvars

4. **"file not found" errors**
   - Remember all files must be git-added for flakes
   - Run `git add .` before testing

5. **"infinite recursion" errors**
   - Usually caused by circular imports
   - Check that host default.nix doesn't import itself

## Benefits After Migration

### 1. Simplified Host Addition

**Before: Adding a new Darwin host required:**
1. Create `hosts/newhost/` directory with `system.nix` and `home.nix`
2. Add host metadata to `variables/default.nix`
3. Add host configuration to `flake.nix`

**After: Adding a new Darwin host requires:**
1. Create `hosts/darwin-newhost/` directory with `default.nix` and `home.nix`
2. Create `outputs/aarch64-darwin/src/newhost.nix` (or appropriate architecture)

### 2. Better Organization

- **Architecture separation**: Clear boundaries between system types
- **Auto-discovery**: No need to manually maintain host lists
- **Scalable testing**: Per-architecture eval tests
- **Rich helpers**: Comprehensive system builders

### 3. Improved Maintainability

- **Consistent patterns**: All hosts follow same structure
- **Less duplication**: Shared helper functions
- **Better debugging**: Haumea provides good error messages
- **Future-proof**: Easy to add new architectures or host types

## Future Enhancements

1. **Additional test types**: NixOS tests for full system validation
2. **Host templates**: Standard patterns for common host types
3. **Specialized generators**: Like ryan4yin's K3s and KubeVirt helpers
4. **Configuration sharing**: Common module patterns across hosts
5. Explore colmena for remote deployment

