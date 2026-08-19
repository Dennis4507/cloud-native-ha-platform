# CGI Challenge — Presentation Map
### Friday 22 August 2026, 16:00 | Luca, Tim, Kevin, Christoph, Raphael

> **Delete this file after the presentation.**

---

## The Requirements (exact from Luca's words, Aug 17)

| # | Requirement | Type |
|---|---|---|
| 1 | Kubernetes cluster via IaC (Terraform / Ansible / script) | **Live demo** |
| 2 | Hello World container — running, accessible | **Live demo** |
| 3 | Pods distributed across 2+ nodes, round-robin traffic | **Live demo** |
| 4 | HPA: scale up AND down on CPU load | **Live demo** |
| 5 | Two clusters in 2 different geographic regions, behind a load balancer. Ingress + valid TLS. | **Live demo** |
| 6 | Monitoring concept: metrics, availability, alerting | Theoretical — explain ideas |
| 7 | Backup & recovery concept: MTTR goal + approach | Theoretical — explain ideas |
| 8 | DNS debugging: one node has DNS resolution issues — how do you investigate? | Theoretical — explain |

Luca's words verbatim: *"6, 7, and 8 are purely theoretical — there is nothing to debate. Just tell us your ideas."*

---

## The Frame — One sentence that sets the tone

Open every demo transition with this mental image. Do not say it word-for-word more than once — let it breathe through the structure:

> "04:09 AM, 19 July 2024. 8.5 million Windows machines go dark. Not a war. Not a hack. A single vendor's update, pushed through one hyperscaler's distribution channel. Every customer of Microsoft Azure woke up to the same failure at the same time."

Everything Denis shows is the answer to: *"How do you build a platform that survives that?"*

---

## Preparation Checklist (before Friday 16:00)

### Must be running before you open the Teams call
- [ ] Azure West EU: K3s cluster, 2 VMs, healthy nodes
- [ ] Azure North EU OR Hetzner Falkenstein: K3s cluster, 2 VMs, healthy nodes
- [ ] Azure Traffic Manager profile with both endpoints, Fast Health Interval enabled
- [ ] Hello World NGINX: 3 replicas, Pod Anti-Affinity `required`, PDB
- [ ] HPA configured (`cpu: targetAverageUtilization: 50`)
- [ ] NGINX Ingress Controller + cert-manager + Let's Encrypt cert (valid, green padlock in browser)
- [ ] ArgoCD App-of-Apps synced on both clusters
- [ ] Uptime Kuma running: both regions green
- [ ] Grafana dashboard open: CPU, pod count, HPA events
- [ ] k9s open in two terminal panes (one per cluster kubeconfig)
- [ ] Architecture diagram rendered (from `diagrams` library or Mermaid in ARCHITECTURE.md)
- [ ] Browser tabs ready: Uptime Kuma | Grafana | ArgoCD UI | Hello World URL (HTTPS)

### Optional but high-impact (deploy if time allows)
- [ ] Velero scheduled backup on Azure Blob
- [ ] Sealed Secrets — one demo secret encrypted in Git
- [ ] Trivy Operator — `kubectl get vulnerabilityreports -A` shows a scan

---

## PRESENTATION MAP

### Total target: 25–30 minutes + questions

```
Act 0  [2 min]   — The problem. Why this exists.
Act 1  [4 min]   — The IaC foundation.          (Req 1)
Act 2  [6 min]   — The running platform.         (Req 2, 3, 4)
Act 3  [7 min]   — The high availability demo.   (Req 5) ← CENTREPIECE
Act 4  [5 min]   — Brain, backup, security.      (Req 6, 7 + bonus)
Act 5  [4 min]   — DNS debugging + bigger picture.(Req 8 + sovereign cloud)
Close  [2 min]   — The lasting impression.
```

---

## ACT 0 — The Problem (2 min)

**Screen:** Architecture diagram (ARCHITECTURE.md Mermaid, or rendered PNG)

**Say:**

> "Before I show you what I built, I want to take 60 seconds to tell you why I built it this way.
>
> In July 2024, 8.5 million machines went dark from a single CrowdStrike update pushed through Microsoft's update infrastructure. Every Azure customer hit the same wall at the same time.
>
> The lesson isn't 'don't use Azure.' The lesson is: a platform that depends on exactly one hyperscaler for its entire stack — compute, DNS, certificate authority, container registry — has exactly one point of failure at the civilizational level.
>
> What I built separates the control plane from the workload plane. The control plane — DNS, Git — lives outside any hyperscaler. The workload plane runs on two independent Kubernetes clusters in two different geographic regions, behind a load balancer that knows within 30 seconds if one of them stops responding.
>
> Everything I'm about to show you answers one question: what does it take to survive that failure scenario?"

**Point at diagram:** Azure West EU → Traffic Manager ← Azure North EU (or Hetzner)

**Transition:** *"Let's start with how it's provisioned."*

---

## ACT 1 — IaC Foundation (4 min) | Requirement 1

**Screen:** VS Code / terminal, `tree terraform/` output, then `ansible/` directory

**What to show in order:**

1. **Terraform directory structure** — `terraform/azure/main.tf`, `variables.tf`, `providers.tf`
   - "Three clean layers: Terraform provisions cloud resources, Ansible configures the OS, cloud-init does the one-time host bootstrap. Each tool does exactly one thing."
   - Point at VMSS resource: "This auto-replaces a failed VM — same mechanism that handles a hardware failure in the cloud."
   - Point at ephemeral OS disk and accelerated networking flags: "These two lines are worth mentioning — ephemeral disk boots 40% faster, accelerated networking bypasses the hypervisor NIC for 30% lower latency."

2. **Run a dry-run** — `terraform plan -out=tfplan` (if cluster is already up, show the state instead)
   - "State is stored in Azure Storage Account — the team can run this from any machine and reach the same cluster."

3. **Ansible inventory** — show `ansible/inventory/hosts.yml`
   - "Same playbook runs against every cloud. Azure nodes, Hetzner nodes — same roles, same result."

4. **Show `kubectl get nodes`** — two nodes, `Ready` status
   - "This is what Luca asked for: two nodes, both Ready, Kubernetes API accessible from my machine."

**Requirement stamp:** ✅ Req 1 — IaC (Terraform + Ansible), `kubectl get nodes` returns 2 Ready nodes

**Wow factor:** Pre-commit hook — show `git commit` triggering `tflint` + `checkov`. "The pipeline blocks a misconfigured security group before it reaches cloud." *Most teams catch misconfigurations in production.*

**Transition:** *"Now let's look at what's running on it."*

---

## ACT 2 — The Running Platform (6 min) | Requirements 2, 3, 4

**Screen:** k9s left pane (West EU), ArgoCD right pane

**Part A — Hello World running (Req 2)**

1. Open `https://your-domain.com` in browser — green padlock, Hello World page loads
   - "Valid TLS certificate from Let's Encrypt via cert-manager. NGINX Ingress terminates TLS and routes to the pods."
   - "The cert auto-renews — no rotation policy to maintain manually."

2. Show the deployment YAML briefly:
   - `replicas: 3`, `image: nginx:alpine` — "Standard NGINX. No custom code, exactly as specified."

**Requirement stamp:** ✅ Req 2 — Hello World running, HTTPS accessible

**Part B — Distributed across nodes (Req 3)**

3. In k9s — navigate to Pods, show which node each pod is on
   - Three pods: one on node-1, one on node-2, one on node-2 (or even 2+1 split)
   - Show the **Pod Anti-Affinity** YAML:
     ```yaml
     affinity:
       podAntiAffinity:
         requiredDuringSchedulingIgnoredDuringExecution:
     ```
   - "The keyword here is `required`. Most teams use `preferred` — which Kubernetes silently ignores under pressure. `Required` is a hard rule: if there's no node without a copy of this pod, Kubernetes queues rather than co-locates."
   - Show **PodDisruptionBudget**: `minAvailable: 2` — "This blocks `kubectl drain` from removing the last eligible pod during a maintenance window."

4. **Round-robin demonstration** — open browser, refresh 5 times, or run:
   ```bash
   for i in {1..5}; do curl -s https://your-domain.com | grep -o "Server: [^<]*"; done
   ```
   - Show different pod/node names in responses

**Requirement stamp:** ✅ Req 3 — Pods distributed, round-robin confirmed

**Part C — Autoscaling (Req 4)**

5. Show the HPA:
   ```bash
   kubectl get hpa -n hello-world
   ```
   - "Currently 3 replicas. Target: 50% CPU. Range: 2–10 pods."

6. **Run k6 load test** — `k6 run k8s/load-test/k6-script.js`
   - Watch k9s in real time — pods scale from 3 → 5 → 7
   - "HPA polls metrics every 15 seconds. Within one minute of sustained load, it's spinning up pods."

7. **Stop k6** — wait 5 minutes (or show a time-lapse clip if presenting as video)
   - Pods scale back down to 2 (the `minReplicas`)
   - "Scale-down has a 5-minute stabilization window by default — prevents thrashing on bursty traffic."

**Requirement stamp:** ✅ Req 4 — HPA scales up AND down on CPU load, live demo

**WOW MOMENT:** GitOps live — while k6 is running, make a one-line change to the NGINX config in Git (bump a version string or change a header value), push, switch to ArgoCD UI. The cluster syncs automatically within ~3 minutes — *while taking live load*. "No kubectl. No SSH. The cluster drives itself to match Git. That's how you manage 50 services without runbooks."

**Requirement stamp:** ✅ Bonus: GitOps — ArgoCD App-of-Apps, live sync

**Transition:** *"Now the requirement that required real architecture decisions: two clusters, two regions, one entry point."*

---

## ACT 3 — High Availability Demo (7 min) | Requirement 5 ← CENTREPIECE

**Screen:** Split 3 ways — Uptime Kuma (left), k9s both clusters (right top/bottom), browser (centre)

This is the theatrical moment. It should feel like a live incident playbook.

**Setup — 90 seconds**

1. Show **Azure Traffic Manager** in the portal or via CLI:
   ```bash
   az network traffic-manager profile show \
     --resource-group rg-ha-platform \
     --name tm-ha-platform --query "properties.dnsConfig"
   ```
   - "Traffic Manager is the global router. It polls both clusters every 10 seconds."
   - Show Fast Interval setting: 10s interval × 3 failures = **30 seconds MTTR**
   - "Default is 30s interval × 3 = 90 seconds. Fast Interval costs $1/month more. Worth it."

2. Show **both clusters healthy** in Uptime Kuma — both green
   - Open `https://your-domain.com` — page loads, green padlock
   - "Right now, Traffic Manager is routing to Azure West EU as the primary endpoint."

3. Show the **ingress YAML** briefly:
   - "NGINX Ingress Controller with cert-manager. The TLS certificate is issued by Let's Encrypt and auto-renewed."
   - "If you want to add a WAF or rate-limiting, that's an annotation."

**Requirement stamp:** ✅ Req 5 — Two clusters, two geographic regions, Traffic Manager load balancer, NGINX Ingress, valid TLS

**The Simulation — 3 minutes** (this is the LIVE money moment)

4. "I'm going to simulate a full regional failure. One NSG rule change — same as what would happen if Azure West EU became unreachable."

   ```bash
   # Block Traffic Manager health probe (simulates region failure)
   az network nsg rule create \
     --resource-group rg-ha-platform \
     --nsg-name nsg-west-eu \
     --name block-health-probe \
     --priority 100 \
     --access Deny \
     --protocol Tcp \
     --destination-port-ranges 80 443
   ```

5. **Watch the clock** — narrate what's happening:
   - T+0: Health probe blocked. West EU cluster still running, Traffic Manager doesn't know yet.
   - T+10s: First failed health check. "Traffic Manager needs 3 consecutive failures before it acts."
   - T+20s: Second failure.
   - T+30s: Third failure. **Traffic Manager removes West EU endpoint.**
   - Uptime Kuma: West EU turns RED.
   - Immediately: North EU turns the only active endpoint.
   - Refresh browser: page still loads. "Zero user-visible downtime."

6. Point at MTTR timestamp in Uptime Kuma: **~30 seconds**

7. **Restore West EU:**
   ```bash
   az network nsg rule delete \
     --resource-group rg-ha-platform \
     --nsg-name nsg-west-eu \
     --name block-health-probe
   ```
   - Traffic Manager re-validates West EU, adds it back: ~30 seconds. Both green again.

**WOW FACTOR — say this slowly:**
> "30 seconds. No human action. No PagerDuty. No war room. The platform detected, rerouted, and continued serving traffic. That's what 'highly available' means — not 'we have redundancy,' but 'redundancy activates itself.'"

**Deeper cut (if time allows):** Mention Liqo for sub-10-second pod migration between clusters. *"For the gap where a cluster is degrading but not fully dead — health probe still passes but pods are failing — Liqo creates virtual nodes that represent another cluster's capacity. Azure's scheduler places pending pods on a Hetzner virtual node. They actually run in Hetzner. This fires in under 10 seconds, before Traffic Manager's 30-second window. Two self-healing layers, not one."*

**Transition:** *"Now — monitoring, backup, security. Luca said these are theoretical. I built them anyway."*

---

## ACT 4 — Brain, Backup, Security (5 min) | Requirements 6, 7 + Bonus

**Screen:** Grafana dashboard

**Monitoring (Req 6) — 2 min**

1. Open Grafana — show the dashboard:
   - Node CPU, memory
   - Pod count over time (the HPA spikes from Act 2 should still be visible)
   - Request rate, error rate

2. "The stack is: OTel Collector as a DaemonSet on every node → Prometheus for metrics → Loki for logs → Grafana Tempo for traces. All three signals, one collector, zero vendor lock-in."

3. Show Uptime Kuma: "This is the availability check layer. It gives us the exact timestamp for MTTR measurement. No guessing."

4. "Alerting: Grafana AlertManager. If CPU across all pods stays above 80% for 5 minutes, it fires to Slack or PagerDuty. The rule is in Git — it gets deployed like any other app."

**Say:** *"If Luca and Tim asked me to replace Grafana with Datadog tomorrow, I change one line in the OTel Collector config. The rest stays the same. That's the value of OpenTelemetry."*

**Requirement stamp:** ✅ Req 6 — Monitoring concept: LGTM stack + OTel + Uptime Kuma + alerting

---

**Backup & Recovery (Req 7) — 2 min**

5. "My MTTR goal is under 4 hours for a full cluster loss. Under 5 minutes for an application-level failure."

6. Show Velero:
   ```bash
   velero backup get
   ```
   - "Scheduled backup runs daily, stored in Azure Blob Storage. The backup also mirrors to Hetzner Object Storage — the backup survives even if Azure Blob is unreachable."

7. **Live restore** (if there's time — high impact):
   ```bash
   kubectl delete ns hello-world
   # pods disappear in k9s
   velero restore create --from-backup latest-backup
   # watch pods come back
   ```
   - "90 seconds to restore a deleted namespace from backup. That's the real MTTR."

8. "Recovery approach: ArgoCD syncs the application state from Git. Velero restores persistent data and secrets. Together: application is back within minutes, not hours."

**Requirement stamp:** ✅ Req 7 — Backup concept: Velero + Azure Blob + Hetzner Object Storage, MTTR < 4h

---

**Security (Bonus) — 1 min**

9. Show Sealed Secrets: `cat k8s/apps/hello-world/secret.yaml` — encrypted blob in Git
   - "No credentials in any file. Safe to push to a public repo. Only the cluster's private key can decrypt this."

10. Show Managed Identity (if time): "VMs authenticate to Azure Key Vault with no passwords — no rotation policy failures, no leaked `.env` files."

**Transition:** *"And the last theoretical question — one node has DNS resolution issues. How do I investigate?"*

---

## ACT 5 — DNS Debugging + The Bigger Picture (4 min) | Requirement 8 + Sovereign Cloud

**Screen:** Terminal (nothing live — this is narrative)

**DNS Debugging (Req 8) — 2 min**

Luca's exact words: *"I don't want the 'Way of Life' answer — delete the node and put a new one next to it. I want the debugging and investigation aspect."*

**Say — deliver this confidently, step by step:**

> "I'd start without touching the node at all.
>
> First, I verify whether the problem is isolated to that node or cluster-wide:
> ```bash
> kubectl exec -it debug-pod -n kube-system -- nslookup kubernetes.default
> ```
> Run this from a pod on the suspected node. If it fails and works from other nodes — the problem is node-local, not CoreDNS.
>
> Next, check CoreDNS health itself:
> ```bash
> kubectl get pods -n kube-system -l k8s-app=kube-dns
> kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
> ```
> If CoreDNS pods are running but logs show upstream timeouts — the node's upstream resolver is unreachable, not CoreDNS itself.
>
> Then inspect the node's DNS configuration:
> ```bash
> cat /etc/resolv.conf       # on the host
> iptables -t nat -L -n -v   # check if DNAT rules for CoreDNS are intact
> ```
> A corrupted iptables state — caused by a kernel update or a node-level network plugin restart — is the most common reason a node loses DNS without CoreDNS being at fault.
>
> Last step: I'd use `tcpdump` on the node to see if DNS packets are actually leaving and returning:
> ```bash
> tcpdump -i any port 53 -n
> ```
> If packets go out but don't come back — it's upstream. If packets never leave — it's iptables or a local firewall rule.
>
> I would not replace the node until I had a root cause. Because if it's an iptables issue triggered by a specific Kubernetes version, putting a new node in won't help — it'll fail too."

**Requirement stamp:** ✅ Req 8 — DNS debugging: isolation methodology, CoreDNS logs, iptables inspection, tcpdump, root cause before remediation

---

**The Bigger Picture — Sovereign Cloud (2 min)**

Bring up the architecture diagram showing 4 clouds.

> "One thing I added beyond the brief — because I think it's the question Luca and Tim will face with customers over the next three years:
>
> The CrowdStrike scenario is a technical failure. But there's a second scenario: the CLOUD Act. US courts can compel Microsoft, Google, and Amazon to produce data stored anywhere in the world. Today. Silently. Without notifying the customer.
>
> Hetzner is a German company. Stackit is Schwarz IT — the company behind Lidl and Kaufland. Both are outside US jurisdiction. If a customer says 'I cannot store sensitive data on US hyperscalers' — the architecture handles that with one routing policy change: Azure drops from priority 1 to priority 5. Hetzner becomes primary. Stackit becomes the warm standby.
>
> [If Stackit is deployed]: Watch the browser. When I flip this one Traffic Manager rule... the page now says 'Served from Schwarz IT — Heilbronn, Germany. German sovereign jurisdiction.' Same application. Different cloud. Same Git repo.
>
> That conversation — 'how does your cloud strategy address the CLOUD Act?' — is going to come up with every German enterprise customer CGI works with."

---

## CLOSE (2 min)

**Screen:** Architecture diagram again, or README on GitHub

**Say:**

> "The goal I set for myself with this challenge was: build a platform that any member of this team could hand to a CGI client and say, 'this is what production resilience looks like.'
>
> Three things I want to leave you with:
>
> First — the 30-second MTTR. Not theoretical. You watched it happen. Clock starts when the health probe fails, traffic reroutes before a human even opens their laptop.
>
> Second — everything in Git. The entire platform state — applications, secrets, RBAC, monitoring rules — is a commit. Recovery isn't restoring from a backup, it's pointing a new cluster at the same repository.
>
> Third — the control plane lives outside every cloud. Cloudflare DNS and GitHub are the only two dependencies that must never go down. If both Azure and Hetzner simultaneously fail, a GitHub Actions workflow provisions AWS Frankfurt in 15 minutes. The DNS pointer is updated. The platform is back.
>
> The platform is designed to survive the Crowdstrike scenario. It's also designed to survive the scenario nobody's naming yet."

---

## Expected Questions — Pre-loaded Answers

**"Why K3s and not AKS?"**
> "AKS charges €75/month per managed control plane. K3s is free. More importantly, K3s runs identically on Azure, Hetzner, and GCP using the same Ansible playbook. AKS locks you at the provisioning layer. K3s is what Rancher uses in production for edge clusters — it's not a development tool."

**"What's your MTTR for a full Azure outage?"**
> "30 seconds for a regional failure — Traffic Manager fires automatically. For a full Azure outage, Cloudflare detects both Azure origins unhealthy after 2 consecutive failures at 30-second intervals — that's 60 seconds. Hetzner cluster is already synced via ArgoCD. No bootstrap time. The application is already running."

**"Is Hetzner production-grade?"**
> "99.9% uptime SLA, ISO 27001, data centers in Germany — GDPR-native by default. Grafana Labs runs their infrastructure on Hetzner. At €8 per node per month versus €35 for an AWS t3.medium equivalent, it's the right cost-resilience trade-off for a warm standby that you hope never activates."

**"How would you scale this to 50 services?"**
> "App-of-Apps in ArgoCD already handles this — adding a service is one YAML file in the `apps/` directory. For metrics at scale, Grafana Mimir replaces local Prometheus storage. For secrets at scale, Vault replaces Sealed Secrets. The skeleton is the same."

**"How long did this take?"**
> "Four days. The architecture diagram was the first hour. Terraform and Ansible took the most time — getting idempotent provisioning right across two regions. The GitOps layer was the fastest part — ArgoCD is designed to be applied with one command."

**"What would you do differently in production?"**
> "Managed control plane on the primary cluster — AKS or EKS — so the Kubernetes API has its own SLA separate from the node pool. On the warm standby, K3s is fine. On the primary, you want a managed etcd. I'd also add Kyverno for policy enforcement — define 'no privileged containers' as a policy, and it's enforced cluster-wide regardless of who's deploying."

---

## Screen Layout for the Live Demo

```
┌─────────────────────────────────────────────────────────┐
│  LEFT PANEL         │  CENTRE            │  RIGHT PANEL  │
│  Uptime Kuma        │  Browser           │  k9s          │
│  (both regions)     │  (hello world URL) │  (West EU)    │
│                     │                    │               │
│                     │                    ├───────────────│
│  Grafana            │                    │  k9s          │
│  (metrics)          │                    │  (North EU)   │
└─────────────────────────────────────────────────────────┘
```

During the failover demo: ArgoCD UI replaces Grafana briefly.

---

## Video Option

If presenting as a recording (Denis confirmed Luca approved this):
- Record at 1080p, no watermarks
- Add chapter markers: Act 0 / Act 1 / Act 2 / Act 3 / Act 4 / Act 5
- Separate 5-min "live failover" clip as the highlight reel — send this first if the video is long
- Upload to YouTube (unlisted) or share via Teams file upload

---

## What This Covers vs. CGI Requirements

| CGI Req | What Denis Shows | Format | Status |
|---|---|---|---|
| 1 — IaC + kubectl access | Terraform plan, Ansible inventory, `kubectl get nodes` | Live | ✅ Covered |
| 2 — Hello World running | NGINX pod, HTTPS URL, green padlock | Live | ✅ Covered |
| 3 — Multi-node, round-robin | k9s pod placement, anti-affinity YAML, curl loop | Live | ✅ Covered |
| 4 — HPA autoscaling | k6 load test → pods scale up → pods scale down | Live | ✅ Covered |
| 5 — 2 regions, LB, TLS | Traffic Manager, two cluster contexts, HTTPS | Live | ✅ Covered |
| 6 — Monitoring concept | LGTM stack walk-through, OTel, Uptime Kuma | Explain + show | ✅ Covered |
| 7 — Backup concept | Velero, MTTR goals, optional live restore | Explain + show | ✅ Covered |
| 8 — DNS debugging | Step-by-step methodology, no node replacement | Explain | ✅ Covered |

### Failover chain — all 4 endpoints live, Hetzner code-ready

Browser stays open the entire demo. Audience watches jurisdiction change live:

```
"Azure West Europe — Amsterdam"          Priority 1  K3s cluster (full K8s demo)
"Azure North Europe — Dublin"            Priority 2  K3s cluster (30s automatic failover)
"Google Cloud — Frankfurt, Germany"      Priority 3  plain NGINX VM  (30s failover, GCP awareness)
"Schwarz IT — Heilbronn, EU sovereign"  Priority 4  plain NGINX VM  (sovereignty mode)
 Hetzner Nuremberg                       Priority 5  Terraform ready, NOT running — last resort
```

GCP = e2-micro free tier, $0. Shows GCP IaC + ACE cert is live.
Stackit = free trial credits. Shows sovereign cloud at infrastructure level, not just diagrams.
Hetzner = code exists, `terraform apply` in 12 min if asked. Nothing running.

### Extras (beyond the brief — introduce naturally, not as a checklist)
| Extra | Wow factor |
|---|---|
| GitOps / ArgoCD App-of-Apps | "One kubectl apply bootstraps everything" |
| Pod Disruption Budget | Most engineers don't know this exists |
| Sealed Secrets | Encrypted secret safe to commit to public Git |
| GCP live endpoint | "I provisioned on GCP — ACE cert is in renewal" |
| Sovereign cloud / CLOUD Act | Stackit in browser — not a diagram, a live endpoint |
| OTel vendor-neutral collector | "Change Datadog to Grafana: one line" |
| Velero dual-cloud backup | Backup survives if Azure Blob is unreachable |
| Ephemeral OS disk + accel networking | Production optimization in Terraform flags |

---

*DELETE THIS FILE AFTER AUG 22, 2026*
