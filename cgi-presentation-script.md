# CGI presentation script — 30 minutes, built in the order it was actually built

> **How to use this document:** this is what to present *from* — the
> README is the thorough reference for CGI to browse before or after, this
> is not that. Structured as the real build order, not requirement-number
> order, because that's how the work actually happened and it reads more
> naturally live. Each milestone is tagged with which requirement(s) it
> answers. Every incident follows the same shape on purpose: **the issue →
> what was actually found → the fix** — not just "it broke, here's the
> fix," because the middle step is the actual proof of real debugging.
> Bold headers are there so you can find your place instantly if a
> question knocks you out of order.

---

## Opening — 1 minute

*"CGI's challenge asks eight questions, but they're really one question:
what happens when a piece of this platform fails, and how much of the
recovery is automatic versus something a human has to notice and fix? I
built this to answer that live. I'll walk it in the order it was actually
built, not requirement-by-requirement, because that's the true story —
and along the way I'll show real problems I hit and fixed, since that's
stronger proof than a demo that looks too clean."*

---

## Milestone 1 — Choosing the server size

**Requirement tag:** Requirement 1 (the infrastructure decision itself)

**What this is:** before any real infrastructure existed, the VM
("Virtual Machine") size for every node had to be chosen. The cheapest
option that could still comfortably run Kubernetes was `Standard_B2s` (2
vCPU, 4 GB memory) — picked specifically to honor the brief's "don't
spend any money" rule as literally as possible.

**The issue:** Azure rejected `Standard_B2s` twice, for two unrelated
reasons.

**What was found (first time):** the design used an "ephemeral" OS disk —
storing the operating system on the VM's own local, free storage instead
of a network disk, for a faster boot at no extra cost. `Standard_B2s`
only has 8 GB of local storage, and the Ubuntu image needed more than
that. Azure didn't reject this at the planning stage — it let 19 of 21
resources succeed, then failed only the two VMSS resources, for exactly
this reason.

**Fix (first time):** switched to a plain network-attached managed disk —
a few cents a month, a slightly slower boot, guaranteed to work on this
size.

**What was found (second time):** `Standard_B2s` was then rejected
entirely, in *both* regions at once, as simply unavailable — a real
Azure capacity restriction on this specific subscription, not a config
mistake. Verified directly against Azure's own SKU ("Stock Keeping Unit"
— Azure's term for a specific VM size) catalog API, rather than guessed.

**Fix (second time):** `Standard_D2s_v3` — not the cheapest possible
size, but a mainstream one with no capacity restriction, confirmed
working in both regions.

**Evidence:**
- `docs/screenshots/13-ephemeral-disk-error.png` — the ephemeral disk rejection
- `docs/screenshots/14-ephemeral-disk-code-fix.png` — the four-line fix
- `docs/screenshots/15-sku-not-available-error.png` — both regions rejecting `B2s` at once
- `docs/screenshots/17-d2sv3-confirmed-germany-west.png` — `D2s_v3` confirmed working

---

## Milestone 2 — Creating our own Azure sandbox

**Requirement tag:** Requirement 1 (the access/governance prerequisite)

**What this is:** CGI's own brief offers an Azure sandbox on request, but
waiting on it didn't fit the 4-day window. Instead, a scoped identity
(`cgi-sandbox`) was provisioned once, from an admin account, with
`Contributor` on exactly two resource groups — nothing subscription-wide,
no permission to grant access to itself or anyone else. Every command
from this point on runs as that identity, not the admin account.

**Evidence:**
- `docs/screenshots/02-entra-sandbox-identity.png` — the two identities side by side, admin vs. sandbox
- `docs/screenshots/04-sandbox-own-view.png` — signed in as the sandbox identity: this is the whole world it can see

---

## Milestone 3 — Terraform: building the actual infrastructure

**Requirement tag:** Requirement 1

**The scaffold, plainly — `terraform/azure/`:**

| File | What it does |
|---|---|
| `providers.tf` | Declares the Azure provider plugin and pins its version |
| `backend.tf` | Points at where Terraform's *state* (its memory of what it built) lives — an Azure Blob container, not this laptop |
| `variables.tf` | Every input value (region, VM size, admin IP) — kept separate from logic |
| `main.tf` | The actual resources: resource group, VNets, NSGs, Load Balancers, VMSS, Managed Identity |
| `outputs.tf` | The public IPs Ansible and the proxy need next |

**Two things worth explaining by name, since they're the two resource
types doing the real work:**

- **VMSS — Virtual Machine Scale Set:** Azure's way of managing a group
  of identical VMs as *one* resource instead of tracking each by hand —
  it can scale the count, replace an unhealthy instance, and roll out
  updates across all of them together. Chosen specifically because
  Requirement 1 needs at least 2 real nodes per region, and Requirement 3
  needs them provably separate.
- **LB — Load Balancer** (Azure Standard Load Balancer): one per region,
  health-probing every VMSS instance on port 80, only routing to
  instances that pass. This is also what drives `automatic_instance_repair`
  — worth mentioning it was briefly *disabled* mid-build, because it kept
  replacing instances before anything was listening on port 80 yet,
  breaking the Ansible inventory each time it fired.

**The issue:** the very first `terraform apply` tried to create a
resource group that already existed from a previous attempt.

**What was found:** Terraform doesn't reconcile with resources it doesn't
already know about — it would have tried to create a conflicting
duplicate rather than manage the real one.

**Fix:** `terraform import`, bringing the existing resource group under
Terraform's management instead of recreating it.

**Evidence:** `docs/screenshots/11-*` / `12-import-successful.png`

---

## Milestone 4 — Ansible: configuring what Terraform built

**Requirement tag:** Requirement 1

**The scaffold, plainly — `ansible/`:**

| File / role | What it does |
|---|---|
| `inventory/hosts.yml` | Every machine Ansible knows about, grouped by role — IPs read straight from Terraform's own output |
| `playbook.yml` | The entry point — runs roles in order: `common` → `k3s-server` → `k3s-agent` → `proxy` |
| `roles/common` | OS prep on every node, every cloud, unmodified — swap off, `br_netfilter`, `ip_forward` |
| `roles/k3s-server` | Installs K3s in server mode on one instance per region — the control plane |
| `roles/k3s-agent` | Joins the second instance per region as a worker |
| `roles/proxy` | Installs NGINX on the GCP node for Requirement 5 |

**Why two separate tools, not one:** Terraform doesn't know how to
configure an operating system; Ansible doesn't know how to create a
VNet. They operate at different layers, and splitting them matches how
the actual work is split.

---

## Milestone 5 — Requirement 1, done

**Say:** *"That's the 'how.' The 'what' is Requirement 1: a Kubernetes
cluster, built entirely through code, verified live."*

**Show:**
```bash
kubectl --context azure-west get nodes
kubectl --context azure-germany-west get nodes
```
Both show 2 `Ready` nodes. **Requirement 1 — done.**

---

## Milestone 6 — Hello World, and HTTPS (Requirements 2 & 4)

**The scaffold:** `k8s/apps/hello-world/base/` holds the Deployment,
Service, and HPA — identical on both regions. Each region's own
`overlays/` folder supplies just the one thing that differs: its own
ConfigMap, with that region's identity text. ArgoCD watches both
overlays and deploys them — this is also the first live proof of GitOps:
deployment by `git push`, not `kubectl apply` by hand.

**Say:** *"Plain NGINX, behind Traefik's ingress, with a certificate
issued automatically by cert-manager."*

**Live links, both real, both already screenshotted with a valid padlock:**
- West Europe: `https://20.229.108.8/`
- Germany West Central: `https://20.218.111.44/`

**The issue:** the first working version showed a valid padlock — but the
certificate itself was wrong.

**What was found:** checking the certificate's actual issuer, not just
its presence, revealed Traefik was silently presenting its own built-in
default certificate instead of the one cert-manager had actually issued.

**Fix:** a `TLSStore` resource, explicitly telling Traefik which
certificate to use as its default.

**Evidence:** the certificate incident section in README, screenshots
`43`/`44` (both regions confirmed fixed).

---

## Milestone 7 — Autoscaling + round-robin (Requirement 3)

**Say:** *"Two things both have to be true: traffic splits across
multiple pods, and more pods get added automatically under load. Shown
together, live, not sequentially."*

**Show:** three panes — `k6` load test, `k9s` watching the `hello-world`
namespace, a curl loop showing the `X-Pod-Name` header alternating. Pods
climb 2 → 6 as load ramps; the curl loop's rotation grows from 2 names to
6 in lockstep.

**The issue:** deploying the fix needed to make round-robin *visible*
(a header showing which pod answered) caused a new pod to get stuck
`Pending` forever.

**What was found:** `kubectl describe pod` showed `0/2 nodes are
available: 2 node(s) didn't match pod anti-affinity rules` — a hard
anti-affinity rule ("never two pods on one node") combined with an HPA
allowed to scale to 10 replicas, on a cluster with only 2 nodes.

**Fix:** the rollout strategy now frees a node before scheduling a
replacement, and the anti-affinity rule was softened to "strongly
prefer, but allow if there's no choice" — a real cost-vs-capacity
trade-off, not a bug fixable by re-reading the YAML.

**Requirement 3 — done.**

---

## Milestone 8 — The GCP showcase: same playbook, different cloud

**Requirement tag:** cherry #2 — deliberately separate from the graded HA path

**The scaffold:** `terraform/gcp/` mirrors the Azure folder shape exactly
(`providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `backend.tf` —
reusing the same remote state backend, just a different key), but
provisions one GCE (Google Compute Engine) instance instead of a scale
set, since this showcase only ever needs one node.

**The real point:** `common` and `k3s-server` run against it completely
unmodified — zero GCP-specific code in either role, because they operate
at the OS level, not the cloud API level. That's the actual proof of
"one playbook, any cloud," not just a claim.

**The issue:** `gcloud auth application-default login` kept reporting
success while silently granting the wrong OAuth scope.

**What was found:** `terraform apply` failed with
`ACCESS_TOKEN_SCOPE_INSUFFICIENT` despite a "successful" login — the
`OAUTHLIB_RELAX_TOKEN_SCOPE` workaround was masking the real problem.

**Fix:** dropped that workaround, explicitly requested only the
`cloud-platform` scope.

**A second issue:** once running, I/O wait hit 91.8% — K3s's own internal
database was timing out talking to itself.

**What was found:** the Always Free tier's disk is HDD-only (`pd-standard`)
— the only storage option it covers — a poor fit for K3s's frequent
small writes, made worse by Traefik and ServiceLB adding their own
constant reconciliation traffic on top.

**Fix:** disabled Traefik and ServiceLB on this one node specifically,
since this showcase never needs either.

**Show:**
```bash
kubectl --context gcp-showcase get nodes
```

---

## Milestone 9 — Building Requirement 5's proxy

**Requirement tag:** Requirement 5 (the build)

**What this is:** a self-hosted NGINX reverse proxy on the GCP node,
routing to West Europe (primary) and Germany West Central (backup) — the
free, self-hosted alternative the brief explicitly allows against a paid
traffic-management service.

**The issue:** installing it became the longest single debugging session
of the build — close to six hours.

**What was found:** two separate problems stacked on each other. First,
Ubuntu's own background update-checker got stuck in an unkillable kernel
state (`D`-state — uninterruptible sleep) on the Always Free tier's slow
disk, blocking the package-manager lock. Second, and the one that
actually mattered most: retrying the install multiple times without
checking whether the previous attempt had exited left **duplicate
`ansible-playbook` processes** fighting over that same lock.

**Fix:** masked the update-checker's triggers, then — the real lesson —
always check `ps aux | grep ansible-playbook` before retrying anything,
never assume a previous run has finished.

---

## Milestone 10 — The live failover demo (Requirement 5, done)

**Say:** *"Watch this from three angles at once: the browser, Uptime
Kuma, and the command line."*

**Show:**
1. Baseline — proxy address shows West Europe; Uptime Kuma all green.
2. `bash scripts/failover-demo.sh break` — blocks West Europe's port 80.
3. Watch — Kuma's West Europe monitor turns red; browser refresh now
   shows Germany West Central; a curl loop shows the same switch live.
4. `bash scripts/failover-demo.sh restore` — watch it rejoin on its own.

**The issue:** the script's first run failed outright.

**What was found:** the NSG rule priority (90) was below Azure's allowed
minimum of 100.

**Fix:** moved to 105 — still evaluated before the existing allow-rule at
120, just inside the range Azure actually accepts.

**Requirement 5 — done.**

---

## Milestone 11 — Requirement 6: monitoring, and Uptime Kuma properly

**What this is:** two layers, not one — Uptime Kuma checks real
endpoints from *outside* the cluster, the same way a visitor's browser
would; ArgoCD's Healthy/Degraded status checks resource correctness from
*inside*. Not redundant: the Milestone 7 deadlock is proof — ArgoCD
caught it immediately, Uptime Kuma saw nothing wrong, because the app
never actually stopped answering real users.

**Show:** the Uptime Kuma dashboard, all three monitors (both regions +
the proxy).

**Written answer:** `requirement-6-monitoring-concept.md` — covers what
"cloud-native" actually means here and the production-scale alternative
(Azure Monitor / Prometheus).

---

## Milestone 12 — Requirement 7: backup & recovery

**What this is:** two scenarios. App-level drift is already solved
live by ArgoCD's `selfHeal`. A whole-region loss recovers by re-running
the same Terraform and Ansible that built it in the first place — a real,
measured 44-minute incident (Milestone 7's deadlock, diagnosed from
scratch) stands in as evidence, not a guess.

**Say:** *"Zero downtime isn't a separate feature here — it falls
straight out of Requirement 5's multi-region design."*

**Written answer:** `requirement-7-backup-recovery-concept.md`

---

## Milestone 13 — Requirement 8: DNS debugging methodology

**What this is:** the TCP/IP model as the investigating framework — work
down from the application to the network interface, narrowing the
search at each layer instead of guessing. Real `tcpdump` capture, a real
firewall rule found and removed, real automatic recovery via `kubelet`'s
own retry.

**Show (if time allows):** `docs/screenshots/90-tcpdump-real-dns-capture.png`

**Written answer:** `requirement-8-dns-debug-runbook.md`

---

## Milestone 14 — Checking the cost claim

**Say:** *"The brief says don't spend any money. GCP genuinely didn't —
verified directly in its own billing report, €0.00. Azure isn't zero,
and I'd rather say that plainly than hide it."*

**Connects back to Milestone 1:** the `D2s_v3` fallback costs 2.5x more
per hour than `B2s` would have ($0.12 vs. $0.048, checked against Azure's
live retail pricing) — the real cost of a genuine capacity limit, not a
design choice.

**Evidence:** `docs/screenshots/88-gcp-zero-cost-confirmed.png`,
`docs/screenshots/89-azure-cost-breakdown.png`

---

## Close — 1 minute

*"Every piece here exists because it answers a specific failure question,
not because it's a technology I wanted to use. Nothing in this platform
worked perfectly the first time, and that's exactly why I kept the real
incidents in, instead of editing them out."*

---

## If asked to go deeper on anything

Full detail on every incident, every command, and every screenshot lives
in `README.md` — the Map at the top links straight to any requirement or
incident by name. Nothing needs to be reconstructed from memory live.
