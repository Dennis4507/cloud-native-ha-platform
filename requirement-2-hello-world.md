# Requirement 2: Hello World container

> CGI's brief: *"A container with any webserver technology should be
> deployed to the cluster. The webserver should be accessible through the
> challengers' browsers and display a simple webpage with a 'Hello World'
> message."*
>
> [Verify against the full brief →](CGI-Challenge-Brief.md#requirement-2)

**In short:** a plain NGINX web server, deployed to both clusters
through GitOps. Pushing to Git is the deploy; nobody runs `kubectl
apply` by hand. Live in a browser on both regions.

## What I built

- **Plain NGINX**, serving a static HTML page. No custom container
  image is needed, just the official image with the page content
  mounted in.
- **Deployed through ArgoCD, following GitOps.** A Git repository is the
  single source of truth for what should be running, and ArgoCD
  continuously watches it and reconciles the cluster to match
  automatically.
- **One ArgoCD installation, on West Europe, manages both clusters
  remotely**, rather than a separate, disconnected install per region.
  One push updates both.
- **Kustomize** organizes the manifests: one shared base (Deployment,
  Service, HPA, Ingress) that both regions build on, plus a small
  overlay per region containing only what's genuinely different, each
  region's own identity text.

## Live demo

- **West Europe:** `https://20.229.108.8/`
- **Germany West Central:** `https://20.218.111.44/`

![Hello World, live over HTTPS, West Europe](docs/screenshots/39-hello-world-west-eu-https.png)
*Above: West Europe's Hello World page, live over HTTPS.*

![Hello World, live over HTTPS, Germany West Central](docs/screenshots/40-hello-world-germany-west-https.png)
*Above: the same page, live on the second region.*

---

## Incidents along the way

**⚠️ One ArgoCD resource was too large for a normal install.**
`kubectl apply` normally stores a full copy of what it applied inside
the object's own metadata, so it can compare against it next time. One
of ArgoCD's own resource definitions exceeded Kubernetes' hard 256KB
limit on that metadata.

![The exact error, one resource too large for a normal apply](docs/screenshots/49-argocd-crd-size-limit-error.png)
*Above: the 256KB annotation limit being hit on ArgoCD's own install.*

Fix: `--server-side`, which tracks the same comparison on the API
server itself instead of inside the object, sidestepping the limit
entirely.

**⚠️ ArgoCD couldn't reach the second cluster.**
Connecting ArgoCD (running on West Europe) to Germany West Central hit
a firewall gap. Azure doesn't treat traffic between two clusters in
different regions as "internal," even inside the same project. Fix: an
explicit firewall rule allowing each region's known addresses to reach
the other's Kubernetes API port.

**⚠️ The certificate tool wasn't installed yet.**
The sync failed a second time. cert-manager, the tool that actually
issues Requirement 4's certificate, had never been installed on either
cluster. The manifests assumed it would already be there.

![cert-manager missing, ArgoCD explaining exactly what it couldn't find](docs/screenshots/35-cert-manager-missing-error.png)
*Above: ArgoCD's own error naming the missing `Certificate` CRD.*

Fix: installed on both clusters using cert-manager's own official
installer.

![cert-manager running on both clusters](docs/screenshots/36-cert-manager-installed-both-clusters.png)
*Above: three pods per cluster, six total, the piece that had been
missing.*

With both gaps closed, ArgoCD's own health checks confirmed both
regions, not just that the command succeeded, but that the application
was actually passing its own readiness checks:

![West Europe, fully synced and healthy](docs/screenshots/37-west-eu-synced-healthy.png)
*Above: West Europe's Application, `Synced` and `Healthy`.*

![Germany West Central, fully synced and healthy](docs/screenshots/38-germany-west-synced-healthy.png)
*Above: the same result, independently, for the second region.*
