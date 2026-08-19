# CLAUDE.md — Build Guide: cloud-native-ha-platform

> **Read this first.** This file is the complete brief for building this project.
> Every architecture decision, security constraint, build sequence, and teaching
> standard is defined here. Follow it exactly.
>
> **Revision note (2026-08-18):** this file was rewritten after re-reading the
> actual CGI brief (PDF: `CGI Automation Challenge - Cloud & DevOps - Cloud &
> DevOps Engineer - Senior 1.pdf`, in Downloads) and deciding to simplify. The
> previous version planned a four-cloud sovereign platform (Azure + Hetzner +
> GCP + Stackit + AWS, CLOUD Act narrative, Liqo cross-cluster peering). That
> is now a documented "portfolio extension, not built" appendix at the bottom
> of this file — not the CGI build. The CGI build is Azure-only for the graded
> requirements, with GCP as one separate, self-contained showcase segment.
> Read the "actual CGI challenge" section below before anything else — it is
> quoted close to verbatim from the real brief, not a paraphrase, because
> paraphrases are exactly where the last version drifted from what was
> actually asked.

---

## Who is Denis and how he learns

Denis Riungu is a DevOps / Cloud Engineer with production experience across:
- eBay listing automation (FastAPI, Celery, FAISS, Vertex AI, K3s on Hetzner, PostgreSQL)
- CloudCommerce DevOps (Jenkins, ArgoCD, K3s on AWS, Prometheus/Grafana/Loki, Trivy, Vault)
- Azure → AWS migration (Terraform 15 modules, DMS CDC, Route 53 blue-green, GitHub Actions)

Denis learns by building — not by reading. He needs every line explained as it is
written: what it does, why it is there, what breaks if it is removed, and what
connects to it. He does not need basic definitions repeated for things he
already knows cold (he knows what a pod is). He does need every acronym and
every non-obvious tool spelled out in full, plain English the first time it's
used in any given document or session — because he is presenting this to a
panel of four CGI professionals (Kevin Sandermann, Cluster Head & Director;
Luca Rodehutskors, Team Manager & Lead Architect; Christoph Schlosser and
Raphael Krüger, Team Managers) who will ask follow-up questions live, and a
half-understood answer is worse than a short, correct one.

**Writing/explaining style for this entire project:**
- Full sentences, not fragments or bullet-soup, when explaining a concept.
- Expand every acronym on first use in a document ("HPA — HorizontalPodAutoscaler"),
  even ones Denis already knows — the goal is a script he could read from cold
  in front of the panel, not just his own understanding.
- Explain the *why*, not the *what* — code and YAML already say what a thing
  does; a good explanation says why it's built that way and what breaks if
  it's removed or misconfigured.
- See the **Acronym glossary** near the end of this file — keep it updated as
  new tools are introduced, and reuse its wording when explaining things in a
  session rather than re-deriving explanations from scratch each time.

**The 3-step rule:** In every build session, complete exactly 3 steps. After step 3,
stop and wait for Denis to confirm before continuing. This keeps sessions focused and
gives Denis time to absorb, test, and ask questions. Never sprint ahead.

**The hand-holding rule:** every step gets built out loud, in chat, not just as
code comments. For each step: build it, then tell Denis in full sentences what
was built, what it connects to, and what to verify — the same pattern as the
"How to run a build session" section below. Comments in the code carry the
*why* for later reference; the chat explanation is what Denis actually reads
in the moment and what he needs to be able to repeat to the panel.

---

## The actual CGI challenge — read this first, always

This is what CGI actually asked for, quoted close to verbatim from the real
brief. Treat this section as the single source of truth above any summary,
any prior conversation, or any narrative built on top of it.

**Framing, from the brief itself:** *"Take the opportunity to demonstrate your
skills and talents."* This is explicitly an open-ended skills demonstration,
not a checklist to tick — CGI's own slide deck frames it that way.

**Parameters:**
- Timeframe: up to 4 days from receiving the brief. Clock started 2026-08-17.
- Using the internet for research is explicitly allowed. Copying an entire
  solution wholesale is explicitly called out as *not* the intent ("what
  script kiddies do").
- **"Use whatever technology or tool you are most comfortable with"** — Ansible,
  Bash, Python, Terraform, PowerShell, or any automation tool are given as
  examples, not a fixed list.
- **"Azure can be used. If you need an Azure sandbox, please contact us."**
  Azure is the cloud CGI explicitly sanctions and can provision access to.
  Nothing in the brief mentions GCP, AWS, Hetzner, or any other provider —
  including GCP in this build is Denis's own strategic choice (the job posting
  was "GCP Cloud Engineer"), not something the challenge asks for.
- **"Have fun, and please don't spend any money on infrastructure services,
  domains, or certificates."** This is a literal, written rule on the
  parameters slide — not a soft preference. It governs every cost decision in
  this file. See "Cost constraint" below for what this rules in and out.
- Deliverable: share a Git repo or any kind of code, and prepare a short
  presentation and demo, presented live over MS Teams to the four recipients
  above.

**The 8 requirements, verbatim intent:**

1. **Deploy a K8s cluster.** ("K8s" = Kubernetes — the platform that runs
   groups of containers across multiple machines and keeps them running.) Can
   be on-premises via any provisioner (Rancher, k3s, kind, kube-spray,
   kubeadm) or a managed PaaS ("Platform as a Service" — a cloud provider runs
   the control plane for you, e.g. AKS on Azure) from a public cloud. Must be
   automated — IaC ("Infrastructure as Code" — infrastructure defined in
   version-controlled files instead of clicked together by hand), a script, or
   a playbook, not manual clicking. **Denis's machine must be able to run
   `kubectl get nodes` and see at least two nodes with status `Ready`.**
2. **Run a "Hello World" container.** Any web server technology, deployed to
   the cluster, reachable from a browser, showing a simple "Hello World" page.
3. **Autoscaling & traffic routing.** The container runs on multiple nodes,
   with traffic distributed to instances by round-robin (each request in
   sequence goes to the next instance in line). Instances scale automatically
   based on CPU load — this is what HPA (HorizontalPodAutoscaler) does.
4. **Ingress controller.** ("Ingress controller" — the component that routes
   external HTTP/HTTPS traffic into the cluster and applies rules like TLS
   termination.) The container is served through one that terminates TLS
   ("Transport Layer Security" — the encryption behind `https://`) and
   returns a valid certificate — **self-signed or CA-signed are both
   explicitly acceptable.** ("CA" = Certificate Authority — a trusted third
   party that vouches a certificate really belongs to who it claims.)
5. **High-available K8s cluster, multi-region.** Design (and *deploy*, "the
   same way as part 1 of the challenge" — meaning via real IaC, not just a
   diagram) a second cluster in a different region. **Traffic routing should
   be simulated with a proxy-server as load balancer, OR with a PaaS
   cloud-native service** — the brief explicitly offers both as valid, which
   matters directly for the cost rule (see below).
6. **Monitoring concept.** *"Describe in high-level terms"* how you'd assess
   the availability of the relevant service endpoints, and which cloud-native
   approach fits. This is a **concept/description requirement**, not
   necessarily a fully deployed observability stack.
7. **Backup & recovery concept.** *"Describe in broad strokes"* how you'd
   handle recovery with two targets: zero downtime, and a maximum MTTR
   ("Mean Time To Recovery" — the average time from something breaking to it
   being fixed) of 4 hours. Also a **concept/description requirement.**
8. **Infrastructure debugging.** Scenario: *"one of your AKS nodes experiences
   DNS hiccups."* ("AKS" = Azure Kubernetes Service, Azure's managed
   Kubernetes.) Find a way to debug and analyze network packets on the node,
   and explain *why* that method was chosen. Note CGI's own scenario is
   phrased around AKS specifically — worth bridging explicitly in the
   presentation even though this build uses self-managed K3s, since the
   underlying DNS/networking stack (CoreDNS, iptables, the node's own Linux
   networking) is the same either way.

**What this means for scope, read against the brief's own words:**
- Requirements 1–5 are the ones that must actually be *deployed and shown
  working live*. That's the graded core of the build.
- Requirements 6 and 7 are explicitly framed as *descriptions* — a clear,
  well-reasoned concept earns full credit. Anything actually deployed for
  these (a live Uptime Kuma dashboard, an actual Velero backup) is a bonus on
  top of an already-sufficient answer, not a requirement.
- Requirement 8 is a debugging *methodology* to explain and demonstrate — it
  doesn't require deliberately breaking DNS live in front of the panel unless
  Denis wants to and is confident it'll go smoothly. A rehearsed walkthrough
  (real commands, real output, captured beforehand) satisfies it.
- "Don't spend any money" is a hard constraint that rules out anything with
  even a trivial ongoing charge unless it's running against infrastructure
  CGI is footing the bill for (their offered sandbox). Default to zero-cost
  paths everywhere; treat any paid service as opt-in only once the funding
  question is actually resolved.

---

## Cost constraint — read literally, not loosely

The brief's own words: *"please don't spend any money on infrastructure
services, domains, or certificates."* This is not "keep costs low" — it's
"spend zero." Build accordingly:

- **No domain purchase.** The Hello World demo doesn't need a real domain —
  raw IPs, or Azure/GCP-provided free subdomains (e.g. a `*.cloudapp.azure.com`
  public IP DNS label, which Azure gives away free per Public IP resource),
  are enough to satisfy "accessible through the challenger's browser."
- **No paid certificates.** Requirement 4 explicitly accepts self-signed
  certificates. Default: `cert-manager` with a `SelfSigned` ClusterIssuer —
  zero cost, zero external dependency, works even with no internet reachability
  during the live demo. (A genuinely CA-signed cert via Let's Encrypt + a free
  wildcard DNS service like nip.io is possible with zero domain cost, but adds
  a dependency on public internet reachability during the demo — worth
  mentioning as "I know how to do this too," not worth risking the live demo on.)
- **Traffic Manager is NOT free** (~$0.54/month base + a small per-query
  charge) — real money, however small, charged to whichever Azure subscription
  it runs on. **Default build target: a free self-hosted proxy** (NGINX or
  HAProxy, running as a container Denis controls) as the Requirement 5 traffic
  router — the brief explicitly names "proxy-server as loadbalancer" as a
  valid, equal alternative to a PaaS service, precisely for situations like
  this. If Denis later gets the CGI-offered Azure sandbox confirmed, swapping
  in Traffic Manager is a documented one-step upgrade (see Phase 4) — but
  don't build on that assumption by default.
- **VMSS size stays Standard_B2s** (2 vCPU, 4GB) — smallest viable for K3s.
  Azure's actual charge for a *running* B2s is small but non-zero; the
  practical answer is the stop/start pattern: `az vmss deallocate` between
  build sessions (no compute charge while deallocated), `az vmss start` before
  a session or the live presentation. This still isn't literally $0 if left
  running, so the discipline matters — stop VMs at the end of every session.
- **GCP must use a genuinely Always-Free resource, not a "cheap" one.**
  Correction from the previous version of this file: GCP's Always Free
  `e2-micro` (or `f1-micro`) tier is **region-locked** to `us-west1`,
  `us-central1`, or `us-east1` — it is **not** free in `europe-west3`
  (Frankfurt), which the earlier plan incorrectly assumed. Since "don't spend
  any money" is literal, the GCP showcase VM runs in one of the actually-free
  US regions. (Verify current terms at cloud.google.com/free before relying on
  this — free-tier terms can change, and this file's knowledge of them has a
  cutoff.) If Denis specifically wants a Frankfurt-region resource for the
  "GCP Cloud Engineer" optics, that's a real trade: it means spending real
  (if trivial) money, or spending GCP free-trial credit (Google's $300/90-day
  trial money, not literally Denis's own) — a decision to make deliberately,
  not by default.
- **Everything else is open source, €0 regardless:** K3s, Ansible,
  NGINX/HAProxy proxy, Uptime Kuma, cert-manager.

---

## Context from CGI interviews — read before each session

**The actual job:** Denis applied for "GCP Cloud Engineer." Luca told him in
Round 1: *"GCP ist eher ein Nischendasein — nicht viel Kundennachfrage."*
("GCP is more of a niche presence — not much customer demand.") The real role
sits in Luca's team: **Private Cloud + Kubernetes + Sovereign Cloud + some
Azure.** This build leans into Azure and Kubernetes depth accordingly — GCP is
included as a deliberate, separate showcase (matching the job posting's
literal title) rather than as the backbone of the architecture.

**GCP strategy (revised):** one Always-Free Compute Engine VM, provisioned by
Terraform, configured by the *same* Ansible playbook used for the Azure
nodes, running a single-node K3s cluster. This is Phase 10 — entirely
separate from the graded multi-region HA demo, which stays on Azure. The
point being proven is "the same automation approach works across cloud
providers," not "GCP is part of the resilience story." Denis also holds a GCP
ACE (Associate Cloud Engineer) certification, currently in its renewal
window — worth one mention in the presentation, then move on.

**Sovereign Cloud is real context, just not this build's job:** Luca's team
is CGI's Sovereign Cloud team, and the CLOUD Act / Hetzner / Stackit
narrative from the earlier version of this project maps directly to what that
team actually does for clients. It's kept as a documented portfolio idea (see
the appendix) precisely because it's a strong *answer* if a panel member asks
"what would you add for a sovereign-cloud client?" — but it isn't part of
what gets built or demoed for this specific 4-day challenge.

---

## Security constraints — non-negotiable

1. Never paste passwords into chat or code files.
2. `.env` stores only LLM API keys and account emails — never passwords.
3. `secrets/` folder is gitignored if it exists.
4. TLS interception is active on Denis's machine — always use
   `truststore.inject_into_ssl()` before any HTTPS call in Python.
5. **NEVER start/stop/restart the interview assistant server** at
   `assistant/`. Denis runs `start_https.bat` himself. This constraint is from
   a real incident that caused 2 hours of broken HTTPS. Do not touch it.
6. All Azure authentication uses User-Assigned Managed Identity or Azure CLI
   login. No static credentials in any file. ARM_* env vars for CI only.

---

## The two-layer project (CGI scope vs portfolio)

This project was started for a CGI Cloud & DevOps Challenge (presentation
date TBD — targeting on or around Aug 22, 2026; confirm the actual date once
CGI schedules the MS Teams session). After the presentation, the CGI-specific
material is trimmed and the project becomes Denis's permanent portfolio piece.

**CGI Challenge scope — the 8 requirements above, mapped to what gets built:**

| Req | What satisfies it | Where |
|---|---|---|
| 1 — K8s cluster via IaC | Terraform + Ansible, K3s on Azure VMSS, 2 nodes minimum, `kubectl get nodes` | Phase 1–2 |
| 2 — Hello World container | NGINX Deployment + Service, ConfigMap-mounted HTML | Phase 3 |
| 3 — Autoscaling + round-robin | Pod anti-affinity (round-robin proof via repeated curl), HPA (k6 load test) | Phase 3 |
| 4 — Ingress + TLS | Traefik ingress (K3s built-in) + cert-manager self-signed cert | Phase 3 |
| 5 — Multi-region HA | Second K3s cluster (North EU) via same Terraform/Ansible, self-hosted proxy failover demo | Phase 1, 2, 4 |
| 6 — Monitoring concept | Written concept doc + lightweight live Uptime Kuma | Phase 5 |
| 7 — Backup/recovery concept | Written concept doc (Velero architecture explained; live install optional bonus) | Phase 6 |
| 8 — DNS debugging | Rehearsed methodology: kubectl exec → nslookup → CoreDNS → node → iptables → tcpdump | Phase 7 |

**The one cherry — deliberately just one:** the GCP showcase (Phase 8). Everything
else that isn't one of the 8 requirements — ArgoCD/GitOps, Sealed Secrets,
Trivy, a full Prometheus/Grafana stack — is cut from the build entirely and
demoted to a one-sentence "here's what I'd add in production" answer, kept
ready in the appendix. The reasoning: every extra live component is something
that can fail during the demo AND something Denis has to hold in his head to
answer questions about. One well-chosen, low-risk differentiator (GCP, tied
directly to the job title, isolated from the graded path) beats several
half-explained ones.

**Separate showcase (not required, not load-bearing for any of the 8):**
GCP Compute Engine, Always-Free tier, single-node K3s via the identical
Ansible playbook. Phase 10.

**Portfolio extensions — documented, not built for CGI.** See the appendix at
the end of this file: Hetzner, Stackit, AWS cold standby, Liqo cross-cluster
peering, sovereignty-mode routing, GCP as a full multi-node HA cluster, GCP
Global Load Balancer, published Terraform modules, the `k8s-guardian` pip
package, MkDocs docs site. These remain good ideas — genuinely relevant to
the Sovereign Cloud team Luca actually runs — but building them now would
mean spending the 4-day window on things that don't answer any of the 8
requirements, and in several cases would violate the literal "don't spend
money" rule. Build them after the presentation, if at all.

---

## Folder structure — what every folder does

```
cloud-native-ha-platform/
│
├── CLAUDE.md                   ← this file — the build guide
├── ARCHITECTURE.md             ← full design reference — STALE, needs a matching
│                                  rewrite to this revised scope (flagged, not yet done)
├── README.md                   ← GitHub-facing project summary
│
├── terraform/
│   ├── azure/                  ← Phase 1: all Azure resources — CORE, already built
│   │   ├── providers.tf        ← azurerm provider declaration + version pin
│   │   ├── backend.tf          ← remote state in Azure Blob (empty/partial config)
│   │   ├── variables.tf        ← all input variables
│   │   ├── main.tf             ← resource group, VNets x2, subnets, Load Balancers,
│   │   │                          VMSS x2, Managed Identity
│   │   └── outputs.tf          ← VMSS/LB public IPs → passed to Ansible + the proxy
│   │
│   ├── gcp/                    ← Phase 10: the GCP showcase VM — CORE (small), not
│   │                              part of the graded HA path
│   │
│   ├── hetzner/                ← portfolio-only. Not part of the CGI build.
│   ├── stackit/                ← portfolio-only. Not part of the CGI build.
│   └── aws/                    ← portfolio-only. Not part of the CGI build.
│
├── ansible/
│   ├── inventory/
│   │   └── hosts.yml           ← Phase 2: IPs from terraform output. Groups:
│   │                              azure_servers, gcp_servers (hetzner/stackit/aws
│   │                              groups exist for portfolio use, unused for CGI)
│   ├── playbook.yml            ← Phase 2: imports roles in order
│   └── roles/
│       ├── common/             ← Phase 2: OS prep — swap off, sysctl, packages.
│       │                          Runs on every node, every cloud, unmodified —
│       │                          this is the proof point for "one playbook,
│       │                          any cloud" used again in Phase 10 for GCP.
│       ├── k3s-server/         ← Phase 2: control plane install
│       └── k3s-agent/          ← Phase 2: worker join
│
├── k8s/
│   └── apps/
│       ├── hello-world/        ← Phase 3: THE core demo app
│       │   ├── configmap.yaml      ← location-identity HTML per cluster
│       │   ├── deployment.yaml     ← NGINX, 2 replicas, required anti-affinity
│       │   ├── service.yaml
│       │   ├── hpa.yaml            ← Phase 3: scale 2→10 on CPU
│       │   ├── ingress.yaml        ← Phase 3: Traefik + TLS
│       │   └── certificate.yaml    ← Phase 3: cert-manager self-signed issuer
│       └── monitoring/
│           └── uptime-kuma.yaml    ← Phase 5: lightweight live monitor
│
│       (no argocd/ or security/ folders — GitOps and Sealed Secrets/Trivy
│        are appendix-only talking points, not built. Deployment is a plain
│        `kubectl apply -f k8s/apps/` per cluster.)
│
├── proxy/                      ← Phase 4: the free self-hosted Requirement-5
│   ├── nginx.conf              ← reverse proxy with 2 upstreams + health checks
│   └── Dockerfile
│
├── .github/
│   └── workflows/
│       └── ci.yaml             ← Phase 9: tflint → checkov → helm lint
│
├── scripts/
│   ├── bootstrap-tfstate.sh    ← Phase 1: DONE — state backend bootstrap
│   ├── kubeconfig-merge.sh     ← Phase 2: merge kubeconfigs, named contexts
│   ├── failover-demo.sh        ← Phase 4: break/restore the primary cluster
│   ├── dns-debug.sh            ← Phase 9: the Req 8 methodology, scripted
│   └── load-test.js            ← Phase 3: k6 script driving the HPA demo
│
└── docs/
    ├── qa/                     ← per-phase Q&A files (this session's own rule)
    ├── ARCHITECTURE.md         ← (see root — stale, pending rewrite)
    ├── monitoring-concept.md   ← Phase 6: Requirement 6's written answer
    ├── backup-recovery-concept.md ← Phase 8: Requirement 7's written answer
    ├── dns-debug-runbook.md    ← Phase 9: Requirement 8's written answer
    ├── failover-runbook.md     ← STALE — written for the old 6-provider chain,
    │                              needs a matching rewrite (flagged, not yet done)
    └── cgi-presentation-script.md ← STALE — needs rewrite to the new Act structure
                                       below. DELETE after the presentation either way.
```

---

## Live demo architecture — what runs vs what's described

```
Requirement-5 routing chain (self-hosted proxy, default):

  self-hosted NGINX/HAProxy proxy (Denis's machine or a free-tier VM)
    ├── upstream 1 (priority): Azure West Europe K3s cluster
    └── upstream 2 (failover): Azure North Europe K3s cluster
  Health check: HTTP GET / every few seconds against each upstream.
  Failover demo: block West EU's health check (NSG rule or firewall toggle)
  → proxy detects it within one or two check intervals → routes to North EU
  → browser shows North EU's identity → restore West EU → proxy re-adds it.

  If the CGI Azure sandbox is confirmed later, Traffic Manager can replace
  this proxy as a one-step swap (same 2 upstreams, DNS-based instead of a
  literal proxy process) — see Phase 4, Step 3 for exactly what changes.

Separate, not in this chain: GCP showcase VM (Phase 10) — its own segment
of the presentation, its own small demo, never a failover target for
Requirement 5.
```

**Location-aware hello-world (the visual core of the Requirement-5 demo):**
Both K3s clusters serve the same HTML structure but with their own identity
baked into a ConfigMap:

```
Azure West EU:  Serving from: Azure West Europe (Amsterdam, Netherlands)
Azure North EU: Serving from: Azure North Europe (Dublin, Ireland)
```

When the proxy fails over, a browser refresh shows the new region — the
panel watches the platform recover, not just hears about it.

---

## How to run a build session

```
Denis says: "let's do Phase X"
Claude reads: this file's Phase X section (and ARCHITECTURE.md once it's
              rewritten to match — flag if it's still stale)
Claude says: "Starting Phase X. Today's 3 steps are: [Step N], [Step N+1], [Step N+2]"
Claude builds Step N — writes the file line by line with inline WHY comments
Claude says, in full plain-English sentences, with acronyms expanded:
  "Step N done. [What was built, what it connects to, what to verify, and
   what question a panel member might ask about it]"
Denis verifies: runs the command, checks the output
Denis says: "good, continue" OR asks a question about what was just built
Claude does Step N+1 the same way
After Step N+2: Claude says: "Phase X complete. What to test before we
                              continue: [list]"
Claude writes docs/qa/phase-X.md covering the teaching points from all 3 steps
Claude waits for Denis to confirm before starting Phase X+1
```

Never skip ahead. Never bundle more than 3 steps in one session unless Denis
explicitly asks to.

---

## Build phases — the complete sequence

### Phase 1 — Terraform Azure foundation ✅ BUILT (2026-08-18)

Resource group (`rg-ha-platform`), two VNets + subnets (West EU, North EU),
one User-Assigned Managed Identity, a Standard Load Balancer + Standard
static Public IP per region (health-probed on TCP:80, feeding
`automatic_instance_repair`), and two `Standard_B2s` VMSS (ephemeral OS disk,
key-only SSH auth, no accelerated networking — B2s doesn't support it).
Written up in full in `docs/qa/phase-1.md`. **Not yet applied against a real
subscription** — that's the first thing to do before Phase 2: `az login`,
`bash scripts/bootstrap-tfstate.sh`, `terraform init -backend-config=...`,
`terraform plan` with a real `admin_ssh_public_key`.

Two things flagged as genuinely uncertain until a real `apply`:
- Whether the Ubuntu 22.04 image fits inside B2s's 8 GiB temp disk for the
  ephemeral OS disk placement.
- The subnets currently have **no NSG** — every VMSS instance is reachable on
  every port from the internet the moment it boots. NSGs land in Phase 2 as
  part of hardening before Ansible connects — don't leave instances running
  unattended before then.

### Phase 2 — Ansible OS config + K3s bootstrap + NSGs (3 steps)

**Step 1 — NSG hardening + inventory + playbook entry point**
Files: `terraform/azure/main.tf` (NSG section, appended), `ansible/inventory/hosts.yml`,
       `ansible/playbook.yml`

Add `azurerm_network_security_group` per region: allow SSH (22) *only* from
Denis's current public IP (a variable, not hardcoded — his IP changes), K3s
API (6443) from the proxy/Denis's IP only, HTTP (80) from anywhere (that's
the whole point of the demo), block everything else. Associate the NSG with
each subnet. This closes the gap flagged at the end of Phase 1.

`hosts.yml` reads IPs from `terraform output -json`. `playbook.yml` imports
roles in order: `common` → `k3s-server` → `k3s-agent`.

Teach: how NSG priority ordering works (lower number = evaluated first, first
match wins), why source IP restriction on SSH matters concretely (an open
port 22 gets automated brute-force traffic within minutes on any cloud —
this isn't theoretical), how Ansible connects (plain SSH, no agent installed
on the target), why role order matters (`k3s-server` needs packages `common`
installs first).

**Step 2 — `common` role (node prep) + `k3s-server` role (control plane)**
Files: `ansible/roles/common/tasks/main.yml`, `ansible/roles/k3s-server/tasks/main.yml`

`common`: disable swap (Kubernetes' scheduler assumes accurate memory
pressure signals, which swap defeats), enable `br_netfilter` (lets the Linux
bridge hand packets to `iptables` — without it, Kubernetes NetworkPolicy
rules silently don't apply), enable `ip_forward` (lets the node route packets
between pods on different nodes).

`k3s-server`: installs K3s in server mode on the first instance of each
region's VMSS, extracts the node-token (needed by agents to join), copies
`kubeconfig` to Denis's local machine for `kubectl` access, saves the token as
an Ansible fact.

Teach: what K3s bundles into one binary (etcd — the cluster's database, API
server, scheduler, controller manager), what the node-token proves (mutual
trust — an agent presenting it proves it's allowed to join this specific
cluster, not just any K3s cluster), how Ansible facts pass values between
roles in the same play without re-connecting over SSH.

**Step 3 — `k3s-agent` role + verify `kubectl get nodes`**
Files: `ansible/roles/k3s-agent/tasks/main.yml`, `scripts/kubeconfig-merge.sh`

Second VMSS instance per region joins as an agent using the server URL +
token from Step 2. `kubeconfig-merge.sh` merges both regions' kubeconfigs
into `~/.kube/config` with named contexts `azure-west` / `azure-north`.

**Verify — this is Requirement 1, satisfied:** `kubectl --context azure-west
get nodes` shows 2 `Ready` nodes. Same for `azure-north`.

Teach: what happens during join (TLS bootstrap handshake, kubelet starts,
node registers itself with the API server), what `NotReady` usually means and
how to check it (`journalctl -u k3s-agent -f` on the node, confirm the API
server on port 6443 is reachable, confirm flannel — K3s's default pod
network — came up), how `kubectl config use-context` switches which cluster
commands target.

### Phase 3 — Hello World: the core demo app (3 steps)

**Step 1 — ConfigMap + Deployment + anti-affinity**
Files: `k8s/apps/hello-world/configmap.yaml`, `deployment.yaml`, `service.yaml`

Each cluster gets its own ConfigMap with its region's identity text, mounted
into NGINX as `index.html` — no custom Docker image needed. Deployment: 2
replicas, `podAntiAffinity` with
`requiredDuringSchedulingIgnoredDuringExecution` (**required**, not
*preferred* — with *preferred*, Kubernetes silently drops the rule under
resource pressure, and the HA guarantee disappears exactly when it matters
most) and `topologyKey: kubernetes.io/hostname` (one pod per node,
enforced — this is what makes Requirement 3's "traffic distributed across
nodes" true rather than aspirational).

**Step 2 — Requirement 3: HPA + round-robin proof**
Files: `k8s/apps/hello-world/hpa.yaml`, `scripts/load-test.js`

HPA: min 2, max 10 replicas, target 60% of the CPU **request** (not the
node's total CPU — if the request is set too low, HPA fires constantly on
noise; this bit Denis before, on the CloudCommerce project). `k6` load test
ramps traffic up, HPA scales pods 2→6→8 live in `k9s`, then scales back down
once load stops.

Round-robin: K3s's built-in Service already load-balances across ready pod
endpoints in round-robin order by default — the proof is simply `for i in
{1..6}; do curl <service-ip>; done` and showing the response alternate
between pods on different nodes.

**Step 3 — Requirement 4: Ingress + TLS**
Files: `k8s/apps/hello-world/ingress.yaml`, `k8s/apps/hello-world/certificate.yaml`

Traefik ingress (built into K3s, no separate install). `cert-manager` with a
`SelfSigned` `ClusterIssuer` — free, no domain, no external dependency, and
explicitly allowed by Requirement 4's own wording ("self-signed or signed by
a public CA").

Teach: what a Service's `ClusterIP` + round-robin `iptables`/`ipvs` rules
actually do under the hood (this is genuinely relevant groundwork for
Requirement 8's DNS/networking debugging discussion later), how
`requiredDuringScheduling` differs from `preferred` in exact scheduler
behavior, HPA's CPU-percent-of-request math, how `cert-manager`'s
`ClusterIssuer` + `Certificate` CRDs (Custom Resource Definitions — types that
extend the Kubernetes API beyond its built-in ones) work together to
auto-renew a cert with zero manual steps.

**Verify:** browser hits the ingress IP over HTTPS, accepts (or shows an
expected self-signed warning for) the cert, shows "Hello World" with the
correct region identity.

### Phase 4 — Requirement 5: multi-region failover demo (3 steps)

**Step 1 — the proxy config**
Files: `proxy/nginx.conf`, `proxy/Dockerfile`

NGINX `stream` or `http` upstream block with 2 servers (West EU ingress IP,
North EU ingress IP), `max_fails`/`fail_timeout` for basic health-check-driven
failover, primary/backup ordering so West EU is preferred while healthy.

**Step 2 — the failover script**
Files: `scripts/failover-demo.sh`

Toggles an NSG rule (or local firewall rule) that blocks the proxy's health
check from reaching West EU, simulating a regional failure, and restores it.

**Step 3 — Traffic Manager as a documented swap-in (not built unless funded)**
Files: this section only, documented, not implemented until the Azure
sandbox question is resolved.

If CGI confirms a sandbox subscription: `azurerm_traffic_manager_profile` +
two `azurerm_traffic_manager_azure_endpoint` blocks (one per region's Load
Balancer Public IP, both already provisioned in Phase 1), Fast Interval
health checks (10s probe, 3 failures = ~30s failover). This replaces the
proxy's job with a DNS-based approach — same demo, different mechanism,
worth knowing both to answer "why not just use Traffic Manager?" live.

Teach: DNS-based failover (Traffic Manager) vs proxy-based failover (NGINX)
— DNS changes what IP a hostname resolves to and depends on client-side TTL
respect; a reverse proxy holds the connection and switches backends itself,
faster and more predictable but is itself a single point of failure unless
it's made redundant too. This tradeoff is exactly the kind of thing a Lead
Architect on the panel is likely to probe.

**Verify — Requirement 5, satisfied:** break West EU, watch the proxy fail
over, browser shows North EU's identity, restore West EU, watch it rejoin.

### Phase 5 — Requirement 6: monitoring concept + lightweight live demo (2 steps)

**Step 1 — the written concept** (this is what actually satisfies Requirement 6)
Files: `docs/monitoring-concept.md`

Written answer to "how would you assess availability of the relevant service
endpoints, and which cloud-native approach fits": HTTP/TLS synthetic checks
against each region's ingress endpoint and against the proxy's public
address; what "cloud-native" options exist (Azure Monitor availability
tests, Uptime Kuma as a lightweight self-hosted option, Prometheus
blackbox-exporter for a fuller stack); how alerting would route (who gets
paged, on what threshold); what's deployed live for this demo vs what's
described as the production-scale answer, and why that's a reasonable
trade-off for a 4-day challenge.

**Step 2 — the lightweight live piece**
Files: `k8s/apps/monitoring/uptime-kuma.yaml`

One Uptime Kuma pod (small footprint, real value for the presentation): HTTP
monitor on each region's endpoint, HTTP monitor on the proxy's public
address. During the Phase 4 failover demo, this is what turns "trust me, it
failed over" into a red-then-green dashboard the panel watches happen with a
timestamp.

Full Prometheus/Grafana/OpenTelemetry stack is explicitly a bonus, not
required — see the appendix if there's time left after the core is solid.

### Phase 6 — Requirement 7: backup & recovery concept (1–2 steps)

**Step 1 — the written concept** (this is what satisfies Requirement 7)
Files: `docs/backup-recovery-concept.md`

Written answer covering: what needs backing up (Kubernetes object state —
Deployments, Services, ConfigMaps — plus any persistent volume data, though
this demo app is stateless), the tool (Velero, backing up to a free-tier
Azure Blob container), the schedule and retention that would be used in
production, and — the actual scored part — **how the design achieves zero
downtime and a ≤4-hour MTTR**: the running application never goes down during
a backup (Velero snapshots don't take the app offline); a *cluster*-level
disaster recovers via `terraform apply` (new cluster, ~15 min) + a plain
`kubectl apply -f k8s/apps/` (stateless app resources, ~minutes) — both are
version-controlled and re-runnable, well inside the 4-hour target, without
Velero being on the critical path at all. Velero's actual job is restoring
anything *stateful* that a redeploy from Git can't reconstruct on its own.

**Step 2 (optional bonus) — live Velero install**
Only if time allows: install Velero, run one real backup, show `velero backup
get`. Not required — the written MTTR reasoning above is what's graded.

### Phase 7 — Requirement 8: DNS/infrastructure debugging methodology (2 steps)

**Step 1 — the runbook**
Files: `docs/dns-debug-runbook.md`, `scripts/dns-debug.sh`

Investigation path, in order, with the reasoning for each step: `kubectl
exec` into a pod and `nslookup`/`dig` the failing name (isolates: is it the
app, or DNS?) → check CoreDNS pods are `Running` and their logs
(`kubectl logs -n kube-system -l k8s-app=kube-dns`) → check
`/etc/resolv.conf` on the node itself (is the node pointed at the right
resolver?) → check `iptables -t nat -L -n -v` (K3s/kube-proxy's rules — is
traffic to the DNS Service IP actually reaching CoreDNS's pod IPs?) →
`tcpdump -i any port 53 -n` on the node (ground truth: are DNS queries
leaving the node at all, and are answers coming back?).

Explicitly bridge Denis's build (self-managed K3s) to CGI's own scenario
wording ("AKS nodes"): the same CoreDNS + Linux networking stack underlies
both — `kubectl`/`tcpdump`-level debugging is identical regardless of who
manages the control plane; the only thing that changes on AKS is that the
control-plane components (etcd, API server) aren't SSH-accessible, which
doesn't affect this specific investigation since it's entirely node- and
pod-level.

**Step 2 — a real captured run**
Deliberately break DNS in a disposable test pod or node (not the live demo
cluster), walk the runbook, capture real command output. This becomes either
a rehearsed live segment or a pre-recorded fallback — reduces risk versus
improvising live in front of the panel.

### Phase 8 — GCP showcase, the one cherry (2 steps, separate from the graded HA path)

**Step 1 — Terraform: one Always-Free Compute Engine instance**
Files: `terraform/gcp/providers.tf`, `variables.tf`, `main.tf`

One `e2-micro` (or `f1-micro`) in a genuinely Always-Free region
(`us-central1` by default — see the Cost constraint section above for why
`europe-west3` doesn't qualify), a firewall rule opening SSH + HTTP/K3s API
the same way the Azure NSGs do, a Service Account with Workload Identity
(GCP's equivalent of Azure's Managed Identity — no key file ever touches
disk).

**Step 2 — same Ansible playbook, single-node K3s**
Files: `ansible/inventory/hosts.yml` (`gcp_servers` group added)

Add the GCP VM's IP to `gcp_servers`. Run the *exact same* `common` +
`k3s-server` roles already built in Phase 2 — no GCP-specific role needed,
because they operate at the OS level, not the cloud API level. A single node
is enough here (this isn't proving Requirement 1 again — that's already
satisfied by the two Azure clusters — it's proving portability).

**Verify:** `kubectl --context gcp-showcase get nodes` shows 1 `Ready` node.
In the presentation, this is its own short segment: "the same Terraform +
Ansible pattern, pointed at a different cloud's API — same playbook, zero
GCP-specific code in it."

Teach: `google_compute_instance` vs `azurerm_linux_virtual_machine_scale_set`
(GCP's per-VM resource vs Azure's scale-set abstraction — different shapes,
same underlying idea), what GCP Workload Identity does (a VM authenticates to
GCP APIs without a downloaded key file, same concept as Azure Managed
Identity, different plumbing), why GCP firewall rules are global objects
attached to a network rather than per-NIC like Azure NSGs.

### Phase 9 — Diagram + docs polish (2 steps)

**Step 1 — architecture diagram**
Files: `docs/architecture_diagram.py`

Python `diagrams` library (same tool used on the CloudCommerce project — see
`docs/architecture_diagram.py` reference at
`C:\Users\OnlyM\Devops Project\cloudcommerce-devops\docs\architecture_diagram.py`
for the working node/edge styling to adapt). Components needed now: Azure
VMSS x2, Azure Load Balancer x2, the self-hosted proxy, GCP Compute Engine
(its own separate box, visually set apart from the Azure HA pair to make the
"not load-bearing" distinction obvious at a glance), Uptime Kuma.

**Step 2 — CI + README badge**
Files: `.github/workflows/ci.yaml`

`tflint` → `checkov` → `helm lint`, on every push. Add the resulting badge to
`README.md`.

### Phase 10 — Presentation preparation (3 steps)

**Step 1 — write the script**
Files: `docs/cgi-presentation-script.md` (rewrite — the existing file is
built for the old 6-provider chain)

Follow the Act structure below. Every line should be something Denis could
say cold, in full sentences, with every acronym expanded on first use per the
writing style rule at the top of this file.

**Step 2 — rehearsal**
Full dry run, timed. Update the script with real numbers (actual failover
time, actual HPA scale-up time) rather than estimates.

**Step 3 — final checklist**
- Both Azure clusters healthy, `kubectl get nodes` clean on both contexts
- GCP showcase node `Ready`
- Proxy correctly routing to West EU, correctly fails over when tested
- Uptime Kuma green on all monitors
- Self-signed cert valid, browser shows Hello World over HTTPS
- Architecture diagram current
- `docs/monitoring-concept.md`, `docs/backup-recovery-concept.md`,
  `docs/dns-debug-runbook.md` all read cleanly start to finish
- VMs started (not deallocated) the morning of the presentation; stop them
  again afterward

---

## Presentation structure

**Opening — do not start with "I'll walk through the 8 requirements":**

> "CGI's challenge asks eight questions, but they're really one question:
> what happens when a piece of this platform fails, and how much of the
> recovery is automatic versus something a human has to notice and fix? I
> built this to answer that question live rather than just describe it."

Straight into the demo. No slide wall first.

**Act 1 — How it's built (Requirement 1)** — 3 min
`terraform`/`ansible` file structure → `kubectl get nodes` on both Azure
contexts, live, 2 `Ready` nodes each. "This is all IaC — Infrastructure as
Code. If I delete these clusters and re-run this, I get the same result
without touching a single manual step."

**Act 2 — What's running (Requirements 2, 3, 4)** — 5 min
Browser → Hello World over HTTPS (Requirement 2 + 4, cert shown). `k9s` →
pods on separate nodes (Requirement 3's anti-affinity). Repeated `curl` →
round-robin alternation. `k6` load test running live in one pane, `k9s` HPA
scaling 2→6→8 in another (Requirement 3's autoscaling).

**Act 3 — The regional failure (Requirement 5)** — 6 min, the centerpiece
Two clusters green in Uptime Kuma → break West EU's health check → Uptime
Kuma goes red → proxy fails over within the check interval → browser refresh
shows North Europe → restore West EU → watch it rejoin. "The user experienced
nothing. The platform detected the failure and rerouted automatically."

**Act 4 — GCP showcase** — 2 min, explicitly separate
"One more thing, separate from the HA story above — the same Terraform and
Ansible pattern, pointed at GCP instead of Azure." `kubectl --context
gcp-showcase get nodes`. "Zero GCP-specific code in the Ansible role — it
operates at the OS level, not the cloud API level."

**Act 5 — Monitoring, backup, DNS (Requirements 6, 7, 8)** — 6 min
Uptime Kuma dashboard (Req 6, plus the written concept doc for the fuller
production answer). Backup/recovery concept walkthrough with the MTTR
reasoning (Req 7). DNS debugging runbook, walked through with real captured
output (Req 8), bridged explicitly to CGI's own "AKS node" framing.

**Close** — 1 min
"Every piece here exists because it answers a specific failure question, not
because it's a technology I wanted to use. That's the thing I'd want you to
take away — not the tool list."

**Timing total:** ~25 minutes + Q&A. Five screens, not fifteen: architecture
diagram, `k9s`, browser, Uptime Kuma, terminal (for the DNS runbook only).

---

## Acronym glossary

Kept current as new tools are introduced. Use this wording (or better) when
explaining any of these live — the goal is a sentence the panel would accept
without a follow-up "sorry, what's that?"

| Acronym | Full form | Plain-English meaning |
|---|---|---|
| K8s | Kubernetes | Software that runs groups of containers across multiple machines and keeps them running, restarting them if they crash. |
| K3s | (a lightweight Kubernetes distribution — not itself an acronym) | A smaller, easier-to-install build of Kubernetes, well-suited to small VMs. |
| IaC | Infrastructure as Code | Defining servers/networks/etc. in version-controlled files instead of clicking them together by hand in a web console. |
| HA | High Availability | Designing a system so a single failure (a pod, a node, a whole region) doesn't take the whole service down. |
| HPA | HorizontalPodAutoscaler | A Kubernetes controller that adds or removes copies of an app automatically based on measured load. |
| PDB | PodDisruptionBudget | A rule that stops voluntary maintenance actions (like draining a node) from taking down more pods than the app can survive losing at once. |
| MTTR | Mean Time To Recovery | The average time between something breaking and it being fixed. |
| TLS | Transport Layer Security | The encryption that makes `https://` connections private and verifies the server's identity. |
| CA | Certificate Authority | A trusted third party that vouches a TLS certificate really belongs to the domain it claims. |
| DNS | Domain Name System | The system that turns a human-readable name (`example.com`) into a machine-usable IP address. |
| NSG | Network Security Group | Azure's firewall rule set, attached to a network interface or subnet, controlling what traffic is allowed in or out. |
| VMSS | Virtual Machine Scale Set | An Azure resource that manages a group of identical VMs together — scaling, replacing unhealthy ones, applying updates as one unit. |
| VNet | Virtual Network | An isolated private network inside a cloud provider, like a data center's internal network but software-defined. |
| CIDR | Classless Inter-Domain Routing | The notation (`10.0.0.0/16`) used to describe a range of IP addresses. |
| RBAC | Role-Based Access Control | Granting permissions by assigning a role (a bundle of allowed actions) to a user or identity, rather than one permission at a time. |
| LB | Load Balancer | A component that spreads incoming traffic across multiple backend servers, and stops sending traffic to ones that fail a health check. |
| CRD | Custom Resource Definition | A way to extend the Kubernetes API with a new object type it didn't originally know about (e.g. `Certificate`, added by cert-manager). |
| PaaS | Platform as a Service | A cloud offering where the provider runs the underlying platform (e.g. the Kubernetes control plane) for you; you just use it. |
| IaaS | Infrastructure as a Service | A cloud offering where the provider gives you raw compute/network/storage and you manage everything on top yourself. |
| AKS | Azure Kubernetes Service | Azure's managed Kubernetes offering — Azure runs and maintains the control plane. |
| GKE | Google Kubernetes Engine | Google Cloud's managed Kubernetes offering (mentioned for context; not used in this build). |
| GCE | Google Compute Engine | Google Cloud's raw virtual machine service — what the GCP showcase VM runs on. |
| IAM | Identity and Access Management | The system controlling who (or what service) is allowed to do what, in a cloud account. |
| CoreDNS | (a DNS server, not itself an acronym) | The DNS server that runs inside a Kubernetes cluster, resolving names like `my-service.my-namespace.svc.cluster.local`. |
| GitOps | (a practice name, not an acronym) | Using a Git repository as the single source of truth for what should be running, with a tool (ArgoCD) continuously reconciling reality to match it. |
| CI | Continuous Integration | Automatically building/testing/checking code on every change, before it merges. |
| ACE | Associate Cloud Engineer | A Google Cloud certification level (entry/associate tier), one of Denis's certifications, currently in renewal. |

---

## Appendix — portfolio extensions, documented but NOT built for CGI

These stay in this file because they're good ideas and directly relevant to
the Sovereign Cloud team Luca actually runs — worth having a ready answer for
if a panel member asks "what would you add next?" None of them are built,
none of them are demoed, and building any of them before the presentation
risks the 4-day budget and the "don't spend money" rule for zero credit
against the 8 actual requirements.

- **Hetzner warm standby** — a German cloud provider, no US parent company,
  not subject to the US CLOUD Act (a US law letting American courts compel
  American companies to hand over data regardless of where it's physically
  stored). Relevant for German public-sector or regulated clients. Terraform
  for this would live in `terraform/hetzner/`, using the same Ansible
  `common`/`k3s-server` roles — the same portability story as the GCP
  showcase, one region further.
- **Stackit (Schwarz IT)** — Lidl/Kaufland's parent company's cloud division,
  BSI C5 certified (the German federal information-security office's cloud
  compliance standard), genuinely no US parent. Same portability story again.
  Could also carry a Secrets Manager story (secrets fetched from an external
  store at runtime instead of living in Git at all, even encrypted) if a
  future version wants a deeper secrets-management narrative than Sealed
  Secrets provides.
- **AWS cold standby** — Terraform written but resources commented out,
  reserved for a GitHub Actions-triggered activation as a last-resort
  fallback if every other provider fails simultaneously.
- **Liqo cross-cluster peering** — lets one Kubernetes cluster borrow compute
  capacity from another, exposed to the scheduler as a "virtual node." A
  genuinely different failure-handling layer than DNS/proxy failover: DNS
  failover reroutes *users*, Liqo reroutes *where a workload actually runs*.
  Real complexity to get right live; not worth the risk in a 4-day window.
- **Sovereignty mode** — a single routing-policy flip that reorders the
  failover chain to prefer EU-sovereign providers (Hetzner, Stackit) first,
  as a response to a CLOUD Act concern or similar policy event. This was the
  previous version's centerpiece narrative — still a strong answer to "why
  would a client want more than 2 regions," just not this challenge's job.
- **GCP as a full multi-node HA cluster** (rather than the single-node
  showcase) — would let GCP genuinely join the Requirement-5 failover chain
  as a third region. Considered and explicitly deferred (see the "GCP's
  role" decision at the top of this revision) to keep the graded demo's risk
  surface small.
- **GCP Global Load Balancer** as an Anycast (routes each user to their
  nearest of 100+ Google points of presence, and can front backends on any
  cloud, not just GCP) routing layer replacing the proxy/Traffic Manager
  entirely. Real cost (~$18/month minimum) — excluded for the same reason
  Traffic Manager is conditional.
- **Full LGTM stack** (Loki + Grafana + Tempo + Prometheus/Mimir) — the
  production-scale answer to Requirement 6, worth describing in the concept
  doc, not worth deploying for a "describe in high-level terms" requirement.
- **Published Terraform modules** on the public registry, a `k8s-guardian`
  pip package wrapping the AI trust-ladder agent, an MkDocs documentation
  site on GitHub Pages, a GitHub Template Repository setup — all genuinely
  good portfolio moves for turning this into something other DevOps teams
  could adopt, none of them answer any of CGI's 8 requirements.
