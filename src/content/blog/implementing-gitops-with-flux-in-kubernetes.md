---
title: 'Implementing GitOps in a Kubernetes Homelab: From kubectl to Flux'
description: 'Managing Kubernetes imperatively was getting old, so naturally I spent way too long automating it'
pubDate: 2025-10-09
---

Project repo: [https://github.com/b4lisong/homelab-k8s](https://github.com/b4lisong/homelab-k8s)

I was tired of manually running `kubectl apply` commands like some kind of ~caveman~ pre-GitOps dinosaur.
More importantly, I was running NixOS—a system built entirely on declarative configuration—while managing
my Kubernetes cluster imperatively. The cognitive dissonance was killing me.

So I decided to implement GitOps with Flux CD. What followed was a journey through bootstrap failures,
unnecessary complexity, and eventually landing on something simple that actually works.

## The Before Times: Imperative kubectl Hell

### What I Had

Before GitOps, my homelab Kubernetes setup was... functional, I guess:

- **k3s cluster** running on NixOS (single-node because I'm not made of money)
- **Traefik** ingress controller (the k3s default)
- **Homepage** dashboard application
- **kubectl apply -k** whenever I remembered to deploy things

The repository structure was beautifully simple:

```
k8s/
  base/
    homepage/
      deployment.yaml
      service.yaml
      ingress.yaml
      configmap.yaml
      # ... RBAC stuff I copy-pasted from the docs
  kustomization.yaml
```

**The workflow:**
```bash
# Make changes locally
vim k8s/base/homepage/deployment.yaml

# Apply manually
kubectl apply -k k8s/

# Cross fingers
```

### The Problems

1. **No Source of Truth**: Git and cluster state diverged constantly. Someone (me) could `kubectl edit` a deployment, and Git would never know. That someone was always me.

2. **Manual Synchronization**: Every change required remembering to run `kubectl apply`. I didn't always remember.

3. **No Audit Trail**: Who changed what? When? Why? Git history helped, but only if I committed before applying (I forgot. A lot.).

4. **Difficult Rollbacks**: Rolling back meant finding the old commit, checking it out, manually applying, and praying I didn't make things worse.

5. **Secrets Management**: Secrets lived... somewhere. In my terminal history? In a random file? ¯\\_(ツ)_/¯ 

6. **Philosophy Mismatch**: Running NixOS, the poster child for declarative everything, while manually kubectl'ing my cluster. It felt icky.

## Why GitOps (Besides "Everyone's Doing It")

### The NixOS Connection

NixOS users get this intuitively:

```nix
# configuration.nix
{
  environment.systemPackages = with pkgs; [ fluxcd kubectl ];

  # Rebuild: sudo nixos-rebuild switch --flake .#
}
```

Your entire system is code. Git is the source of truth. Rollbacks are `nixos-rebuild --rollback`.

**GitOps brings this same philosophy to Kubernetes.** Finally.

### The GitOps Promise

GitOps means:
- Git repository = single source of truth
- Automated synchronization (pull-based, controllers do the work)
- Declarative infrastructure (just like NixOS!)
- Easy rollbacks via `git revert`
- Complete audit trail in commit history

For my homelab, this meant:
- **Experimentation without fear**: Break something? `git revert && git push`
- **Reproducibility**: Destroy the cluster, re-bootstrap, identical state
- **Learning by doing**: Actually understand how these controllers work
- **Foundation for growth**: Start simple, add complexity when (if?) I need it

## The Migration: A Journey of Overengineering and Course Correction

### Step 1: Choosing Flux CD

I evaluated the two main GitOps tools:

| Tool | Pros | Cons | My Take |
|------|------|------|---------|
| **ArgoCD** | Beautiful UI, mature, everyone uses it | Requires database, more moving parts | Too heavy for my homelab |
| **Flux** | Lightweight, just Kubernetes CRDs | No UI (CLI only) | Perfect for learning |

**Decision: Flux**

For a single-person homelab where I'm trying to learn, Flux's simplicity won. It's just Kubernetes resources.
No extra databases. No fancy UI I'd look at once and never again.

### Step 2: Repository Restructuring (The Easy Part)

I reorganized to follow Flux conventions:

```
homelab-k8s/
├── clusters/bh/              # Cluster-specific Flux config
│   ├── apps.yaml            # Points to apps/
│   └── infrastructure.yaml  # Points to infrastructure/
│
├── apps/                     # Application deployments
│   ├── homepage/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── configmap.yaml
│   │   └── kustomization.yaml
│   └── kustomization.yaml
│
├── infrastructure/           # Future: monitoring, cert-manager, etc.
│   └── kustomization.yaml   # Currently empty
│
└── k8s/                     # OLD structure (will delete after validation)
```

**Key change**: Separation of cluster config (`clusters/bh/`) from application manifests (`apps/`).

### Step 3: Flux Bootstrap (Where Things Got Interesting)

I planned to use GitHub personal access tokens, but then I remembered this is a **public repository**.
SSH deploy keys are simpler and more secure for public repos (they're scoped to one repo, don't expire randomly, etc.).

```bash
# Generate SSH key for Flux
ssh-keygen -t ed25519 -C "flux-homelab-bh" -f ~/.ssh/flux-homelab-bh

# Add public key to GitHub as Deploy Key
# (Settings → Deploy keys → Add deploy key → check "Allow write access")
cat ~/.ssh/flux-homelab-bh.pub

# Bootstrap Flux
flux bootstrap git \
  --url=ssh://git@github.com/USERNAME/homelab-k8s \
  --branch=main \
  --path=./clusters/bh \
  --private-key-file=~/.ssh/flux-homelab-bh
```

**What this does:**
1. Installs Flux controllers into the cluster
2. Creates a `GitRepository` resource pointing to the repo
3. Creates `Kustomization` resources for infrastructure and apps
4. Stores SSH private key as a Secret (encrypted in cluster)
5. Commits Flux manifests back to `clusters/bh/flux-system/`

This part worked. I was shocked. Of course, the shock was premature...

### Step 4: Defining Kustomizations (Still Going Well)

The `clusters/bh/` directory has two key resources:

**infrastructure.yaml** - Deploys infrastructure first:
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 10m0s
  retryInterval: 1m0s
  timeout: 5m0s
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure
  prune: true     # Remove resources deleted from Git
  wait: true      # Wait for resources to be ready
```

**apps.yaml** - Deploys apps after infrastructure:
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 5m0s
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps
  prune: true
  wait: true
  dependsOn:
    - name: infrastructure  # Apps wait for infrastructure
```

**The `dependsOn` is critical**: Infrastructure must be ready before apps deploy. Order matters.

### Step 5: The Complexity Trap (Oh No)

Here's where I got ~stupid~ ambitious. I tried to implement **image automation**—the feature where
Flux automatically updates container images when new versions are released.

This required resources like:

```yaml
# ImageRepository - scans container registry
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: homepage
spec:
  image: ghcr.io/gethomepage/homepage
  interval: 1m0s

# ImagePolicy - decides which versions to use
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: homepage
spec:
  imageRepositoryRef:
    name: homepage
  policy:
    semver:
      range: 1.x.x  # Only 1.x.x versions
```

**The problem:** Bootstrap failed. Repeatedly. With cryptic errors about CRDs not existing.

**The root cause:** Image automation requires **extra controllers** not included in base Flux bootstrap:
- `image-reflector-controller`
- `image-automation-controller`

These aren't installed by default. You need to either:
1. Add `--components-extra=image-reflector-controller,image-automation-controller` to bootstrap
2. Install them later via manifests in `infrastructure/`

I spent *hours* debugging this. Reading logs. Checking CRDs. Googling error messages.

**The lesson:** Start simple. Understand core GitOps before adding automation layers.

**The fix:** I deleted all image automation. Gone. Removed. Burned from my mind.

Now version updates are manual:

```yaml
# apps/homepage/deployment.yaml
spec:
  containers:
  - name: homepage
    image: ghcr.io/gethomepage/homepage:v1.5.0  # Fixed version
```

**To upgrade:**
```bash
# Edit the version
vim apps/homepage/deployment.yaml
# Change v1.5.0 → v1.6.0

# Commit and push
git add apps/homepage/deployment.yaml
git commit -m "upgrade homepage to v1.6.0"
git push

# Flux applies automatically within 1-5 minutes
```

This is **simpler, more controlled, and I actually understand it**. Perfect for learning. I can add
image automation later once I actually know what I'm doing.

## The Current State: Simple, Working GitOps

### Architecture

```
Git Repository (GitHub)
  ↓
GitRepository Resource (Flux polls every 1m)
  ↓
Kustomization: infrastructure (reconciles every 10m)
  → (currently empty, ready for future additions)
  ↓
Kustomization: apps (reconciles every 5m, after infrastructure)
  → Homepage Deployment
  → Homepage Service
  → Homepage Ingress
  → Homepage ConfigMap
  → RBAC resources
```

### The New Workflow (So Much Better)

```bash
# 1. Make changes locally
vim apps/homepage/configmap.yaml

# 2. Commit to Git
git add apps/homepage/configmap.yaml
git commit -m "update homepage dashboard layout"
git push

# 3. That's it! Flux handles the rest:
#    - Detects commit within 1 minute
#    - Reconciles apps/ within 5 minutes
#    - Applies changes to cluster
#    - Prunes old resources if removed from Git
```

No more `kubectl apply`. No more "did I deploy this?" uncertainty. Git is the source of truth.

### Verification Commands

```bash
# Check all Flux resources
flux get all

# View Kustomization status
flux get kustomizations

# Force immediate reconciliation (when I'm impatient)
flux reconcile kustomization apps --with-source

# View logs (for debugging, which I do often)
flux logs --kind=Kustomization --name=apps --follow
```

## Lessons Learned (The Hard Way, As Usual)

### 1. Simplicity Beats Automation (Initially)

I spent hours trying to implement image automation before realizing:
- Manual version updates are fine for a homelab
- Understanding core GitOps > fancy automation features
- Complexity can be added later, incrementally
- ~FOMO is not a good architectural principle~

### 2. Public Repos Need Different Auth

GitHub personal access tokens work, but SSH deploy keys are better:
- Scoped to a single repository (more secure)
- Don't expire randomly like tokens might
- Easier to manage for public repos
- No need to worry about token permissions

### 3. CRDs Matter

I tried to create a Traefik Middleware resource and got:
```
Error: no matches for kind "Middleware" in version "traefik.containo.us/v1alpha1"
```

**The lesson:** Custom Resources require Custom Resource Definitions. If Traefik is installed via k3s defaults,
it might not include all CRDs. Don't blindly create CRs without ensuring CRDs exist first.

(I removed the Middleware. It was just for security headers anyway. Not critical for a homelab.)

### 4. Bootstrap Order Is Critical

Flux bootstrap only installs core controllers:
- source-controller
- kustomize-controller
- helm-controller
- notification-controller

**NOT included:**
- image-reflector-controller
- image-automation-controller

If you need those, you must:
- Add `--components-extra=...` to bootstrap, OR
- Install them via manifests in `infrastructure/`

Don't assume. Check.

### 5. NixOS + GitOps = Perfect Match

Both embrace:
- Declarative configuration
- Reproducibility
- Git as source of truth
- Atomic updates

**NixOS flake integration:**
```nix
{
  environment.systemPackages = with pkgs; [
    fluxcd
    kubectl
  ];
}
```

Rebuild, and you have Flux. Declarative infrastructure all the way down.

## Adding New Applications (The Easy Part Now)

The beauty of GitOps: adding apps is just creating files and pushing to Git.

### Example: Adding nginx

**1. Create application manifests:**

```bash
mkdir -p apps/nginx
```

**apps/nginx/deployment.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
```

**apps/nginx/service.yaml:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: nginx
spec:
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
```

**apps/nginx/namespace.yaml:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nginx
```

**apps/nginx/kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
```

**2. Update parent kustomization:**

**apps/kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - homepage
  - nginx  # Add this line
```

**3. Commit and push:**

```bash
git add apps/nginx/
git add apps/kustomization.yaml
git commit -m "feat: add nginx application"
git push
```

**4. Flux deploys automatically!**

```bash
# Watch it happen
kubectl get pods -n nginx --watch

# Or force immediate reconciliation (because I'm impatient)
flux reconcile kustomization apps --with-source
```

No `kubectl apply`. No manual steps. Just Git.

## Managing Configuration Changes

### Before (Imperative, ew):

```bash
kubectl edit configmap homepage-config -n homepage
# Make changes in vim (probably break YAML syntax)
# Save and exit
# Hope it works
# No audit trail
# No rollback plan
```

### After (GitOps - yay!):

```bash
# Edit locally with your editor of choice
vim apps/homepage/configmap.yaml

# Make changes, validate YAML locally
# Commit with descriptive message
git add apps/homepage/configmap.yaml
git commit -m "feat: add PostgreSQL monitoring to homepage dashboard

Added PostgreSQL to Services section.
Updated layout to 4 columns for better visibility."

git push

# Flux applies changes within 5 minutes
# Git history preserves the 'why'
# Rollback is trivial
```

### Rollback Example

Something broke? No problem:

```bash
# Find the problematic commit
git log --oneline

# Revert it
git revert abc1234

# Push
git push

# Flux automatically rolls back to previous state
```

**Or, if you want to go nuclear:**

```bash
git reset --hard <good-commit>
git push --force

# Flux reconciles to that state
# (Use with caution, but it works)
```

## Security: Secrets Management (Future Problem)

This setup currently has **no secrets in Git** because Homepage doesn't need any. When I add apps
that do need secrets, I have options:

### Option 1: Sealed Secrets

```bash
# Encrypt secrets that only the cluster can decrypt
kubectl create secret generic db-password \
  --from-literal=password=hunter2 \
  --dry-run=client -o yaml | \
kubeseal -o yaml > apps/myapp/sealed-secret.yaml

# Commit encrypted secret to Git (safe!)
git add apps/myapp/sealed-secret.yaml
```

### Option 2: SOPS + Age

```yaml
# .sops.yaml
creation_rules:
  - path_regex: .*.yaml
    encrypted_regex: ^(data|stringData)$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3...
```

```bash
# Encrypt secret in place
sops --encrypt --in-place apps/myapp/secret.yaml

# Commit encrypted file
git add apps/myapp/secret.yaml
```

Flux decrypts automatically if configured with SOPS key.

### Option 3: External Secrets Operator

Point to external secret stores (Vault, AWS Secrets Manager, etc.).
This will probably be my method of choice. Secrets in a repository, even encrypted, in a private repo, give me the heebie-jeebies.

**For now:** Not needed. I'll cross that bridge when I need secrets that aren't just `password123`.

## Infrastructure Evolution

Currently, `infrastructure/` is empty. In the future, it might contain:

**Monitoring Stack:**
```
infrastructure/
  monitoring/
    prometheus/
    grafana/
    kube-state-metrics/
```

**Certificate Management:**
```
infrastructure/
  cert-manager/
    crds.yaml
    deployment.yaml
    letsencrypt-issuer.yaml
```

**The pattern remains the same:**
1. Add manifests to `infrastructure/`
2. Commit and push
3. Flux deploys
4. Profit (or at least learn something)

## Challenges I Overcame (Barely)

### Challenge 1: Bootstrap Failures

**Problem:** ImagePolicy resources failing with "no matches for kind ImagePolicy"

**Root cause:** Image automation controllers not installed

**Solution:** Remove image automation, embrace simplicity

**Lesson:** Understand base Flux before adding extensions

### Challenge 2: CRD Dependencies

**Problem:** Traefik Middleware failing with "no matches for kind Middleware"

**Root cause:** k3s-provided Traefik doesn't install Middleware CRDs by default

**Solution:** Remove optional middleware (wasn't critical anyway)

**Lesson:** Verify CRDs exist before creating Custom Resources

### Challenge 3: Reconciliation Timeouts

**Problem:** `kubectl wait` timing out on infrastructure Kustomization

**Root cause:** Waiting for resources that couldn't deploy due to other issues

**Solution:** Debug with `kubectl describe kustomization`, fix root issue

**Lesson:** Flux + kubectl debugging work together, use both

## Measuring Success

### Before GitOps

- **Deploy time**: Manual, whenever I remembered
- **Rollback**: Stressful, error-prone, "where's that old commit?"
- **Audit trail**: Git history (if I committed before applying, which I often didn't)
- **Cluster state visibility**: `kubectl get all -A` and hope
- **Drift detection**: None whatsoever

### After GitOps

- **Deploy time**: 1-5 minutes after push
- **Rollback**: `git revert && git push`
- **Audit trail**: Complete Git history with commit messages
- **Cluster state visibility**: `flux get all` shows everything
- **Drift detection**: Flux corrects it automatically every 5 minutes

### The Numbers

**Time from decision to working GitOps:** ~4 hours of iteration (mostly fighting image automation)

**Lines changed:** ~700 lines (mostly new manifests and documentation I'll probably never read again)

**Failed attempts:** 3 (all image automation related)

**Final solution:** Simple, maintainable, actually works

## Recommendations for Future Me (And Others)

### Start Simple

Don't try to implement everything at once:
- ❌ Image automation
- ❌ Advanced RBAC
- ❌ Multi-cluster management
- ❌ Helm repositories
- ❌ Full monitoring stack

**Start with:**
1. Bootstrap Flux
2. Deploy one simple app
3. Understand reconciliation
4. Add complexity incrementally (or don't, simple is fine)

### Use SSH for Public Repos

Personal access tokens work, but SSH deploy keys are:
- Scoped to one repo
- Easier to revoke
- Don't expire randomly
- One less thing to rotate

### Match Your Deployment Model

- **Single cluster homelab**: Simple structure (like mine)
- **Multi-cluster**: Use `clusters/<name>/` directories
- **Multi-environment**: Use Kustomize overlays or branches

## Future Plans (Maybe)

### Phase 2: Monitoring

Add Prometheus + Grafana to `infrastructure/monitoring/`:
- Cluster metrics
- Application metrics
- Pretty graphs I'll look at once

### Phase 3: More Apps

Expand `apps/` with:
- Database (PostgreSQL)
- Cache (Redis)
- Actually useful things

### Phase 4: Multi-Cluster

When (if?) I add a second cluster:
```
clusters/
  bh/           # Homelab cluster
  production/   # Future production cluster (ambitious)
```

### Phase 5: Advanced Flux

Once I'm comfortable with basics:
- Image automation (properly this time)
- Helm repositories
- Notification webhooks
- Progressive delivery (Flagger)

But that's Future Me's problem.

## Conclusion

GitOps with Flux transformed my homelab from "manually running kubectl and hoping" to "Git is the source of truth and everything just works."

The result:

✅ **Reproducible**: Destroy the cluster, re-bootstrap, identical state
✅ **Auditable**: Every change in Git history
✅ **Automated**: Push to Git, Flux deploys
✅ **Recoverable**: Rollback via `git revert`
✅ **Scalable**: Add apps without increasing complexity

**For NixOS users especially**, GitOps feels natural. We already manage our OS declaratively; extending
that to Kubernetes just makes sense.

### Key Takeaway

**Start simple. Master the basics. Add complexity deliberately.**

Image automation, advanced RBAC, multi-cluster management—all valuable, but not on day one.
Get GitOps working with one app. Understand the reconciliation loop. Watch Flux logs. Debug failures.

**Then** maybe add more. Or don't. Simple is fine.

---

**Repository Structure:**
```
homelab-k8s/
├── clusters/bh/           # Flux cluster configuration
│   ├── apps.yaml
│   └── infrastructure.yaml
├── apps/                  # Applications
│   └── homepage/
├── infrastructure/        # Infrastructure (empty for now)
└── docs/                 # Documentation for future me
```

**Useful Commands:**

```bash
# Bootstrap Flux
flux bootstrap git \
  --url=ssh://git@github.com/USER/REPO \
  --branch=main \
  --path=./clusters/bh \
  --private-key-file=~/.ssh/flux-key

# Check status
flux get all
flux get kustomizations

# Force reconciliation
flux reconcile kustomization apps --with-source

# View logs
flux logs --kind=Kustomization --name=apps --follow

# Suspend/resume (for maintenance)
flux suspend kustomization apps
flux resume kustomization apps
```

---

GitOps isn't just a deployment strategy—it's a mindset. Git becomes the interface to your infrastructure.
Changes are code reviews. Rollbacks are `git revert`. Your cluster is a pure reflection of your repository.

For a NixOS homelab, this feels like coming home. Everything is code. Everything is in Git. Everything is reproducible.

*Now I just need to actually deploy some useful applications instead of just Homepage.*

---
Project repo: [https://github.com/b4lisong/homelab-k8s](https://github.com/b4lisong/homelab-k8s)
