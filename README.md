# cloud-native-ha-platform

**By Denis Riungu**

## What this is

My submission for CGI's Cloud & DevOps Challenge: a high-availability
Kubernetes platform, built entirely through code.

There are two identical Kubernetes clusters, one in Azure West Europe
and one in Germany West Central, provisioned with Terraform and
configured with Ansible. A small Hello World web app runs on both,
spread across multiple servers, so losing one server never takes it
down. If a whole region fails, traffic moves to the other region
automatically.

Beyond what the challenge asks for, there are two extras I call the
Cherries:

- A Google Cloud server, provisioned with the same automated
  deployment (Terraform and Ansible).
- A GitOps pipeline, using ArgoCD and GitHub (not GitHub Actions), so
  deployments happen by pushing to Git instead of running commands by
  hand.

![Full architecture diagram, showing GitHub as source of truth, ArgoCD managing both Azure regions, the GCP node running K3s and the failover proxy](docs/architecture.png)
*Above: Green arrows are GitOps (ArgoCD pulling from Git). Blue is real traffic.
Dashed brown is one-time infrastructure provisioning. GitHub Actions is
shown as planned, not yet built.*

## The build pipeline: scaffold and commands together

The diagram above shows what talks to what while the platform is
*running*. The five phases below show how it gets *built*, and they
all use the same three shapes, so this key only needs reading once
(Phase 5 adds one more arrow idea, explained where it appears):

```mermaid
flowchart LR
    L1(["A file"]) -->|tells| L2[["A command"]]
    L2 -->|produces| L3["The result"]
    L0["Earlier result"] -->|needed first| L2
```

A file tells a command what to do. A command produces a result. A
result can also be needed first, when a command depends on it already
existing.

**Phase 1: provisioning the infrastructure**

```mermaid
flowchart LR
    F0(["scripts/bootstrap-tfstate.sh"]) -->|tells| CMD0[["Run: bash bootstrap-tfstate.sh"]]
    CMD0 -->|produces| OUT0["Remote state storage created in Azure Blob"]

    TFAZ(["terraform/azure/main.tf"]) -->|tells| CMD1[["1. terraform plan<br/>2. terraform apply"]]
    BEAZ(["terraform/azure/backend.tf"]) -->|tells| CMD1
    PROVAZ(["terraform/azure/providers.tf"]) -->|tells| CMD1
    VARAZ(["terraform/azure/variables.tf"]) -->|tells| CMD1
    OUT0 -->|shared Remote state storage, needed first| CMD1
    CMD1 -->|produces| OUT1A["4 Azure VMs in 2 separate regions"]
    CMD1 -->|produces| OUT1B["Load Balancer in both Azure regions"]
    CMD1 -->|produces| OUT1C["Public IP per node, for Ansible to SSH in"]

    TFGCP(["terraform/gcp/main.tf, outputs.tf"]) -->|tells| CMD2[["1. terraform plan<br/>2. terraform apply"]]
    BEGCP(["terraform/gcp/backend.tf"]) -->|tells| CMD2
    PROVGCP(["terraform/gcp/providers.tf"]) -->|tells| CMD2
    VARGCP(["terraform/gcp/variables.tf"]) -->|tells| CMD2
    OUT0 -->|shared Remote state storage, needed first| CMD2
    CMD2 -->|produces| OUT2["GCP bare Ubuntu VM, also hosts the failover proxy"]
    CMD2 -->|produces| OUT2IP["Public IP, for Ansible to SSH in"]
```

Three more files exist under `terraform/` but aren't in the diagram, they were not writen by hand:

- **`.terraform.lock.hcl`**: gets written automatically after running `terraform init`. It
  Records the exact AzureRM provider version that got downloaded from the Terraform Registry eg (`3.117.1`) plus a set of cryptographic hashes that confirm that exact download hasn't been tampered with.
- **`backend-config.hcl`**: Contains the environment-specific details telling Terraform where the remote state is stored. this file contains resource_group_name  = "rg-tfstate", storage_account_name = "stcnhptfstate6e2d"
container_name = "tfstate" & key = "azure.tfstate" needed during Terraform init 
We Gitignore this file because these values are specific to our Azure environment/subscription
- **`.terraform/`**: Terraform's local working directory, created by terraform init. It contains locally downloaded provider binaries/modules and Terraform's initialized backend metadata. For example, this is where Terraform keeps the downloaded AzureRM provider that it needs to communicate with Azure. (the real `azurerm` or `google` program itself), so it doesn't need to download it again on the next run.

**Phase 2: installing Kubernetes**

```mermaid
flowchart LR
    HOSTS(["ansible/inventory/hosts.yml"]) -->|tells| CMD3[["Run: ansible-playbook<br/>roles: common, k3s-server,<br/>k3s-agent, proxy"]]
    PLAY(["ansible/playbook.yml"]) -->|tells| CMD3
    COMMON(["roles/common/tasks/main.yml"]) -->|tells| CMD3
    K3SSRV(["roles/k3s-server/tasks/main.yml"]) -->|tells| CMD3
    K3SAGT(["roles/k3s-agent/tasks/main.yml"]) -->|tells| CMD3
    PROXY(["roles/proxy/tasks/main.yml"]) -->|tells| CMD3
    CMD3 -->|produces| OUT3A["K3s is joined on every node"]
    CMD3 -->|produces| OUT3B["The failover proxy is installed on the GCP VM"]
    CMD3 -->|produces| OUT3C["3 raw kubeconfig files fetched to my laptop"]
```

`ansible/inventory/hosts.yml:` Connects Phase 1 (Terraform) to Phase 2 (Ansible). After Terraform creates the VMs, their public IP addresses are added here so Ansible knows which machines to connect to and what role each machine has.

**Note:** cert-manager is not installed by Ansible. It is installed separately later in Phase 3 as part of the Kubernetes/GitOps setup.

Two supporting files sit inside the proxy Ansible role. They aren't shown separately in the diagram because they're used internally by roles/proxy/tasks/main.yml:

- `templates/nginx.conf.j2` — the NGINX configuration template. Ansible fills it with the correct regional IP addresses and deploys it to the proxy server.
- `handlers/main.yml` — reloads NGINX when that configuration changes. The task triggers it automatically using notify.

Simply put: main.yml installs/configures the proxy → nginx.conf.j2 defines how traffic should be routed → the handlers/main.yml reloads NGINX to apply the change.

**Phase 3: deploying through GitOps**

```mermaid
flowchart LR
    IN3["The 3 raw kubeconfig files, produced by Phase 2"] -->|needed first| CMD3B[["Run: bash kubeconfig-merge.sh"]]
    F3B(["scripts/kubeconfig-merge.sh"]) -->|tells| CMD3B
    CMD3B -->|produces req1| OUT3B["kubectl is reachable from my laptop"]

    OUT3B -->|needed first| CMD4[["Run: kubectl apply, k8s/argocd/"]]
    F4(["k8s/argocd/: 3 Application files,<br/>one per region plus uptimekuma 4 monitoring"]) -->|installs and tells| CMD4
    CMD4 -->|produces| OUT4["ArgoCD now runs and watches the Github repo we set up"]

    OUT3B -->|needed first| CMDCM[["Run: kubectl apply<br/>cert-manager's official installer"]]
    CMDCM -->|produces| OUTCM["cert-manager is running on both clusters"]

    F5A(["k8s/apps/hello-world/"]) -->|tells| CMD5[["Run: git push"]]
    F5B(["k8s/apps/monitoring/"]) -->|tells| CMD5
    OUT4 -->|needed first| CMD5
    OUTCM -->|needed first| CMD5
    CMD5 -->|produces| OUT5A["Hello World App is live in both Azure regions"]
    CMD5 -->|produces| OUT5B["Setup Uptime Kuma to watch both Azure regions & the GCP hosted proxy"]
```

k8s/apps/hello-world/ — contains the Kubernetes YAML files that define how the Hello World application runs: its pods, Service, autoscaling, HTTPS/Ingress, and related configuration.
k8s/apps/monitoring/ — contains the Kubernetes YAML files that define how Uptime Kuma monitoring runs and how it is exposed.

They are shown as single folders here to keep the diagram manageable. In Phase 5 We will expands both folders and explains the individual Kubernetes files inside them.

**Phase 4: Live Test & Demo — Proving Requirements 3 & 5**

These are repeatable live tests against the already-running platform. Nothing new is being built here — we deliberately create load and failure conditions to prove the platform behaves as designed.

```mermaid
flowchart LR
    APP["Hello World running"] -->|needed first| LOAD[["Run k6 load test"]]
    LOADFILE(["scripts/load-test.js"]) -->|tells| LOAD
    LOAD -->|produces| SCALE["Requirement 3 proof:<br/>HPA scales 2 → 6 pods<br/>under CPU load"]

    APP -->|needed first| FAIL[["Run failover demo"]]
    FAILFILE(["scripts/failover-demo.sh"]) -->|tells| FAIL
    FAIL -->|produces| REGION["Requirement 5 proof:<br/>West Europe is blocked<br/>Traffic automatically reroutes to Germany"]
```

**Phase 5: what's inside the app manifests (what ArgoCD deploys)**

Phases 1–4 showed commands I run directly. Phase 5 is different: I don't run these Kubernetes files one by one. They describe how the application should run, and ArgoCD uses Kustomize to deploy and keep that configuration in sync automatically.

You don't need to follow every file in the diagram. The main flow is:

ConfigMaps provide configuration → Deployment runs the pods → Service sends traffic to them → HPA scales them → Ingress exposes them → Certificate provides HTTPS → Kustomize brings everything together for ArgoCD.

```mermaid
flowchart LR
    NS(["base/namespace.yaml"]) -->|holds every resource here| DEPLOY(["base/deployment.yaml"])
    NGINXCONF(["base/nginx-config.yaml"]) -->|provides ConfigMap:<br/>hello-world-nginx-conf| DEPLOY
    CM(["overlays/west-eu/configmap.yaml"]) -->|provides ConfigMap:<br/>hello-world-html| DEPLOY
    DEPLOY -->|selected by| SVC(["base/service.yaml"])
    DEPLOY -->|scale target of| HPA(["base/hpa.yaml"])
    SVC -->|routed to by| ING(["base/ingress.yaml"])
    ISSUER(["base/cluster-issuer.yaml"]) -->|signs cert for| CERT(["overlays/west-eu/certificate.yaml"])
    CERT -->|provides Secret:<br/>hello-world-tls req4| ING
    CERT -->|provides Secret:<br/>hello-world-tls req4| TLSSTORE(["overlays/west-eu/tls-store.yaml"])
    ING -->|tells| KUST(["overlays/west-eu/kustomization.yaml"])
    HPA -->|tells| KUST
    TLSSTORE -->|tells| KUST
    KUST -->|tells| CMD[["ArgoCD builds automatically:<br/>kustomize build"]]
    CMD -->|produces| RESULT["Hello World is live in West Europe"]
```

*Monitoring uptimekuma & K6, use the same principle, far fewer moving parts:*

```mermaid
flowchart LR
    NS2(["namespace.yaml"]) -->|holds every resource here| DEPLOY2(["deployment.yaml"])
    PVC(["pvc.yaml"]) -->|provides claim:<br/>uptime-kuma-data| DEPLOY2
    DEPLOY2 -->|selected by| SVC2(["service.yaml"])
    SVC2 -->|tells| KUST2(["kustomization.yaml"])
    KUST2 -->|tells| CMD2[["ArgoCD builds automatically:<br/>kustomize build"]]
    CMD2 -->|produces| RESULT2["Uptime Kuma watches both regions and the proxy"]
```
That completes the Kubernetes/GitOps side of the platform. The two diagrams show how the individual Kubernetes files work together, but the main takeaway is simple: ArgoCD and Kustomize turn these manifests into the running platform automatically.

The end result is Hello World running and scalable in both Azure regions, with Uptime Kuma monitoring both regions and the failover proxy. These are the same running components used in the live load and failover demonstrations.

Every file under k8s/apps/hello-world/ and k8s/apps/monitoring/ is represented here, so anyone interested in the implementation can follow the diagrams and trace exactly how the pieces connect.

## My Whys — Why I Built It This Way

- **Why Terraform? Portability without starting from scratch.**
  I already have a reusable Terraform scaffold from previous projects. The provider may change between Azure, GCP or another platform, but the workflow stays familiar: init → plan → apply. This portability has made it easier for me to move infrastructure between hyperscalers, PaaS and self-managed environments when business needs or costs change. (Kept me Cloud Agnostic) and i can claim proficiency provisioning infra in cloud and baremetal its also a professional choice.
- **Why Ansible? → Repeatable configuration across clouds.**
  Terraform builds the infrastructure; Ansible configures what runs on it. My Ansible roles only care about Linux + SSH, not which cloud owns the VM. The same common and k3s-server roles used for Azure can therefore configure the GCP node without being rewritten.
  Terraform gives me infrastructure portability; Ansible gives me configuration portability.
- **Why K3s instead of AKS? → Direct node access.**
  Requirement 8 required node-level DNS/network troubleshooting. With K3s on ordinary VMs, I can SSH directly into a node (4 live demo) & ability to tools such as tcpdump to see tcp Packets, ip, ss, iptables and journalctl. AKS would have introduced a couple of more processes trying to reduce operational overhead, but here that abstraction would work against what I wanted to demonstrate, and i am not accustomed with AKS given myoptions above. sticking to scope of the busines and where u make the largest impact given the vaast nature of Cloud Computing.and For this challenge, seeing underneath Kubernetes was more valuable.
- **Why NGINX instead of Azure Traffic Manager? → Visible, low-cost failover.**
  Traffic Manager is a managed, metered Azure service. NGINX gives me the functionality this project actually needs — health-check both regions, detect a failure and reroute traffic — without adding another paid service. It also makes the failover mechanism completely visible during the live demo.
  Same requirement, less cost, and easier to demonstrate.
- **Why Uptime Kuma + k6 instead of Prometheus + Grafana? → Right-sized observability.**
  Prometheus and Grafana would be straightforward to add, but they would consume additional CPU, memory and storage on nodes where I was deliberately trying to maintain a very small, low-cost footprint. specially for this challenge where i was instructed not to use my Money, Uptime Kuma gives me the availability/response monitoring I need, while k6 generates & measures the load used to demonstrate scaling. I chose the smallest observability stack that could convincingly prove the requirements and coz i wanted to do a live demo, prometheus and grafana would have been resource intensive.
- **Why Standard_D2s_v3 instead of cheaper B2s VMs? → Actual regional capacity.**
  B2s was my preferred cheaper option, but Azure reported no available capacity for this subscription/region. D2s_v3 therefore wasn't an architectural preference; it was the practical fallback. The cheapest SKU on the pricing page doesn't help if the cloud can't actually provision it.
- **Why self-signed TLS instead of a public CA? → Meet the requirement without unnecessary dependencies.**
  The requirement was to demonstrate HTTPS/TLS and explicitly allowed self-signed certificates.
  A publicly trusted certificate would introduce a domain and external dependency that wasn't necessary for the challenge. I added what the requirement needed, not infrastructure simply for the sake of having it.
- **Why GCP separately? → Prove portability without risking the core demo.**
  The Azure environment proves the actual multi-region High Availablity requirements. GCP answers a different question: "How much of my automation survives if I change cloud providers?" Terraform can changes providers, while the same Ansible roles continue to work. Keeping GCP outside the HA path also means an experimental multi-cloud component can never break the graded Azure failover demonstration. and also sticking with the Job title GCP Engineer

## Map: jump straight to what you need

**Checking a claim against CGI's actual wording?** [CGI-Challenge-Brief.md](CGI-Challenge-Brief.md)
contains the original brief, requirement by requirement, exactly as CGI sent
it. Every page below links straight to its own section of it.
  **Each requirement below has its own short page covering:**

*What was required → What I built → How I prove it live → What went wrong and what I learned.*
| # | What was asked | What I built, in one line | Full detail |
|---|---|---|---|
| 1 | Kubernetes cluster, built through code | 2 independent clusters, Terraform + Ansible, verified live | [`requirement-1-kubernetes-cluster.md`](requirement-1-kubernetes-cluster.md) |
| 2 | "Hello World," reachable in a browser | Deployed by GitOps: pushing to Git is the deploy | [`requirement-2-hello-world.md`](requirement-2-hello-world.md) |
| 3 | Round-robin traffic + autoscaling under load | 2 to 6 pods live under real load, round-robin proven at the same time | [`requirement-3-autoscaling-roundrobin.md`](requirement-3-autoscaling-roundrobin.md) |
| 4 | Ingress with a valid TLS certificate | Traefik + cert-manager, self-signed, auto-issued | [`requirement-4-ingress-tls.md`](requirement-4-ingress-tls.md) |
| 5 | Multi-region HA with automatic failover | A second cluster + self-hosted proxy, live failover demo | [`requirement-5-multi-region-ha.md`](requirement-5-multi-region-ha.md) |
| 6 | Monitoring concept | Two-layer approach, plus a live dashboard | [`requirement-6-monitoring-concept.md`](requirement-6-monitoring-concept.md) |
| 7 | Backup & recovery concept | Two scenarios, backed by a real measured incident | [`requirement-7-backup-recovery-concept.md`](requirement-7-backup-recovery-concept.md) |
| 8 | DNS debugging methodology | TCP/IP-model-framed, real commands, real evidence | [`requirement-8-dns-debug-runbook.md`](requirement-8-dns-debug-runbook.md) |

**We also few extra milestones were part and parcel of bringing the whole project to life. They weren't necessarily CGI requirements, but they tell a big part of the engineering story:**

### Real incidents Below — check them out, there's a lot to learn.
Things broke along the way. I documented the problem → investigation → root cause → fix rather than hiding the failures. They show how the platform was actually built and debugged in practice.

### The GCP VM, provisioned the same way as the Azure VMs — proving portability.
I provisioned a separate GCP VM using the same Terraform approach. Compare the Azure and GCP Terraform scaffolds and you'll notice they are largely the same structure and workflow — the main difference is the cloud provider and its resources. The same Ansible roles from Azure then configure the GCP machine with little/no cloud-specific change.

**Why this matters to me:** it keeps the architecture slippery. If a hyperscaler becomes too expensive or stops making business sense, moving should be an engineering decision, not a complete rebuild.

### Building My own cgi-sandbox environment.
Rather than working from an unrestricted Azure account, I created a dedicated sandbox identity/environment using Microsoft Entra ID, Azure Resource Groups and scoped permission due to Time and Sandbox CGI never arrived.
It was also an opportunity to demonstrate knowledge of, RBAC, resource isolation and least privilege alongside the main Kubernetes work.

### Cost claims backed by evidence.(screenshots)
The Two VMss in the Two Azure regions wer not completel free as you will see in the screenshots below, but GCP server was 0.00 as proven

**Real incidents hit and fixed during the build.** Worth knowing these
exist on their own, since they're some of the strongest evidence this
was actually built and debugged, not just described:

| Incident | What happened | Where |
|---|---|---|
| The wrong certificate | Browser showed Traefik's default cert, not the real one, from a `TLSStore` misconfiguration | [`requirement-4-ingress-tls.md`](requirement-4-ingress-tls.md) |
| GCP OAuth scope + severe I/O wait | `gcloud` silently granted the wrong scope; the Always Free tier's disk caused 91.8% I/O wait | [The GCP showcase](#the-gcp-showcase-cherry-2) |
| The six-hour proxy install saga | A stuck update-checker, then duplicate `ansible-playbook` runs fighting over the same lock | [`requirement-5-multi-region-ha.md`](requirement-5-multi-region-ha.md) |
| The NSG priority rejection | The failover script used an invalid Azure priority value, 90, below the allowed minimum | [`requirement-5-multi-region-ha.md`](requirement-5-multi-region-ha.md) |
| The pod-scheduling deadlock | A hard anti-affinity rule and a mismatched autoscaler limit left a pod permanently stuck | [`requirement-3-autoscaling-roundrobin.md`](requirement-3-autoscaling-roundrobin.md) |
| The B2s capacity limit | The cheaper VM size had zero available capacity, forcing a 2.5x costlier fallback | [Checking the cost claim](#checking-the-cost-claim-not-just-asserting-it) |

## Provisioning CGI Sandbox Account & Keeping this project isolated from everything else

CGI's own challenge brief offers a sandbox Azure environment on request,
but there wasn't time to wait on that request inside a tight four-working day 
window where i was only able to work after Bedtime. 
Instead, I provisioned my own equivalent sandbox for the sake of speed

- **Two accounts, split by role.** The Root account only ever acted as
  the administrator that set the boundary up once. A second,
  deliberately limited identity Account, `CGI Challenge Sandbox`, is where we does all of
  the actual build work.
- **A hard boundary around the project.** The sandbox identity's access
  is restricted to exactly the two resource groups this project uses, so
  the project can never accidentally reach, or be reached by, anything
  else already in the same account.
- **No standing permission to expand its own access.** The sandbox
  identity holds only the specific permissions it needs to do its job,
  not the ability to grant itself, or anyone else, that is only reserved for Root Account

![Resource groups, isolated from other work](docs/screenshots/01-resource-group-isolation.png)
*Above: The two resource groups this project owns, sitting alongside an
unrelated resource group already in the account: proof this project has
its own clean space, not a shared one.*

![Two identities: administrator and sandbox](docs/screenshots/02-entra-sandbox-identity.png)
*Above: The Two separate identities in The Root administrator account
that set the identities up, & the sandbox identity that actually builds
the challenge.*

![Scoped permissions, not full access](docs/screenshots/03-rbac-scoped-roles.png)
*Above: The actual access breakdown on the Terraform state resource group: the
administrator holds full ownership, while the sandbox identity holds
only the specific permissions it needs to do its job, with no permission
to grant access to anyone else, including itself.*

![The sandbox identity's own view](docs/screenshots/04-sandbox-own-view.png)
*Above: Signed in as the sandbox identity itself, this is the only reality it
can see: exactly the two resource groups this project owns, and nothing
else.*

### Incident — Terraform Finding Resources That Already Existed

We started the project by running terraform apply and Terraform refused because we had created created Sandbox resources manually before Terraform ran, Terraform didnt know so Instead of trying to overwrite or duplicate them, it safely stopped.

Fix: I used terraform import to bring the existing resource groups under Terraform management without recreating them.

Lesson: If infrastructure already exists, Terraform doesn't automatically assume ownership — you need to explicitly import it.

Small Azure detail: A resource group's region only describes where Azure stores the resource group's metadata. It does not determine WHERE the resources inside that group must run. So this had no impact on the platform's actual multi-region design.

![Terraform correctly refusing to duplicate an existing resource](docs/screenshots/11-apply-rg-conflict.png)
*Above: Terraform noticing the resource group already exists and stopping,
rather than silently creating a conflicting duplicate.*

![Import successful](docs/screenshots/12-import-successful.png)
*Above: The fix: bringing the existing resource group under Terraform's
management with `terraform import`, rather than recreating it.
IP address and SSH key, are redacted for Security reasons.*

**Everything past this point is EXTRA, CGI requirements, installing Kubernetes, 
deploying Hello World App through GitOps, the autoscaling demo, the TLS certificate, & the
multi-region failover, have own page.** Scroll back up to the
[Map](#map-jump-straight-to-what-you-need) above for Requirements 1
through 8, each with its own live and lived evidence & its own incidents. 

**Whatfollows here is everything the Map doesn't cover: the GCP showcase, the real cost numbers, & one long debugging story. (Feel Free to Read It You might learn something)**

### The GCP showcase (cherry #2)

GCP (Google Cloud Platform) is the one deliberate differentiator tied
directly to the actual job title this project was written for. The
point being proven is that the same Terraform and Ansible pattern works
identically on a completely different cloud provider, not that a third
region joins the failover story. This VM never runs Hello World and is
never a failover target. It's its own separate showcase, and it also
ends up hosting Requirement 5's proxy as an independent process. See
[requirement-5-multi-region-ha.md](requirement-5-multi-region-ha.md) for
why the proxy has to live outside both Azure regions to do its job.

**Getting the account itself set up** took its own sequence: a fresh GCP
project, isolated from an existing unrelated project already on the same
account (the same reasoning as the separate Azure sandbox identity), the
Compute Engine API enabled, and a billing account linked. That last part
is required by Google even to stay entirely within the Always Free tier;
it's not itself a sign of anything being charged.

![Project creation and billing linked](docs/screenshots/51-gcp-project-and-billing-setup.png)
*Above: A dedicated project, isolated from other work on the same account, with
billing linked, required before Google allows almost anything, free
tier or not.*

**Authenticating Terraform to actually use the account** turned out to
be the first real snag. `gcloud auth application-default login` kept
completing "successfully" while quietly granting a narrower permission
scope than requested. That was only confirmed once an actual `terraform
apply` failed on it directly:

![Insufficient scope, even though login reported success](docs/screenshots/53-gcp-insufficient-scope-error.png)
*Above: `ACCESS_TOKEN_SCOPE_INSUFFICIENT`. The credential file existed and
looked valid, but didn't actually carry the permission Terraform needed
to create anything.*

The fix was requesting exactly one scope explicitly, `cloud-platform`,
instead of the default bundle of several, which stopped Google's
consent screen from silently narrowing what got granted. Once that was
sorted, the same remote state backend already built for Azure could
just be reused. A different `key`, the filename within that same
storage account, keeps this project's state separate from Azure's,
without needing an entirely separate GCP-native backend just for one
small VM.

![Terraform initialized against the reused backend](docs/screenshots/52-gcp-terraform-init-success.png)
*Above: Same Azure storage account, same backend, a different key: no reason
to build a second one just because the resources being tracked happen
to be on a different cloud.*

![Terraform apply complete, 8 resources, real IP](docs/screenshots/54-gcp-terraform-apply-complete.png)
*Above: Network, firewall rules, a dedicated identity with no key file, a
static IP, and the VM itself, all live.*

**Then Ansible, same roles, unmodified:**

![The inventory, with the new host added](docs/screenshots/55-gcp-inventory-diff.png)
*Above: One new entry, in the same `k3s_server` group as both Azure regions. A
single K3s server is already a complete cluster on its own, so no
worker node was needed.*

![Ansible reaching the new VM successfully](docs/screenshots/56-gcp-ansible-ping-success.png)
*Above: Confirming SSH actually works, before touching anything else.*

![K3s installed fresh on the GCP node](docs/screenshots/57-gcp-first-k3s-install-play-recap.png)
*Above: The same `common` and `k3s-server` roles already proven on Azure,
pointed at a different cloud's API entirely, with zero GCP-specific
code in either role.*

![The merge script updated for a third cluster](docs/screenshots/58-kubeconfig-merge-gcp-diff.png)
*Above: Same script, same reasoning, one more region added to what it merges.*

**Then the second real incident.** `kubectl` against the new cluster
failed with a TLS handshake timeout, a different and more interesting
problem than a firewall block (already ruled out, since the IP matched
and a raw TCP connection to the port succeeded). The actual cause was
visible directly in K3s's own logs on the node:

![K3s's own internal queries taking over a minute](docs/screenshots/59-gcp-slow-sql-tls-timeout-log.png)
*Above: Database queries that should take milliseconds were taking 8, 38, even
over 60 seconds. K3s's own components were failing to reach K3s's own
API in time, which is exactly why a request from outside also timed
out.*

![91.8% of CPU time spent waiting on disk](docs/screenshots/60-gcp-io-wait-91-percent.png)
*Above: Not a CPU or memory problem: `%wa` (I/O wait) confirms the disk itself
was the bottleneck.*

The root cause: the Always Free tier's storage allowance is specifically
standard, spinning-disk (HDD) persistent disk, confirmed directly from
Google's own documentation before considering any fix, since switching
to faster storage would have introduced real, ongoing cost. K3s's
internal datastore does frequent small writes, which is a poor fit for
that specific kind of disk, and every extra default component (Traefik,
K3s's built-in ServiceLB) added its own constant reconciliation traffic
on top of an already-struggling disk. Neither is needed here, since this
showcase never runs an app requiring an ingress controller or a
LoadBalancer Service, so both got disabled specifically for this one
node, and K3s was cleanly reinstalled.

![I/O wait gone after disabling unneeded components](docs/screenshots/61-gcp-io-wait-fixed-after-reinstall.png)
*Above: `%wa` dropped from 91.8% to 0.0%, confirmed before even attempting
`kubectl` again.*

![The GCP node, Ready, reached directly from the laptop](docs/screenshots/62-gcp-showcase-ready-final.png)
*Above: All three clusters, two Azure regions and this one, now live in a
single merged kubeconfig, each reachable by its own context.*

### Checking the cost claim, not just asserting it

The brief's "don't spend any money" rule deserves real evidence, not
just a paragraph promising it was followed.

**GCP is genuinely €0.00**, confirmed directly in Google Cloud's own
billing reports for the `cgi-challenge-ha-platform` project, covering
the full build window:

![GCP billing report showing exactly €0 for the whole build](docs/screenshots/88-gcp-zero-cost-confirmed.png)

**Azure is not €0.** Worth saying plainly rather than hiding it. Cost
Management, scoped to `rg-ha-platform`, shows real charges: the two
running VMSS instances (`vmss-...eu west`, `vmss-...de west central`)
are the largest line items, plus small amounts for the Load Balancers'
Public IPs and disks:

![Azure Cost Management, itemized by resource](docs/screenshots/89-azure-cost-breakdown.png)

That's not a contradiction of the "spend zero" rule, for a specific
reason. GCP's Always Free tier is a genuinely permanent, zero-cost offer
for one small VM. Azure has no equivalent free tier at the scale this
project actually needs: a real Kubernetes cluster, in two regions, is
Requirement 1 and Requirement 5's literal graded deliverable, not an
optional extra the brief's rule was written to rule out. The brief's own
wording targets "infrastructure services, domains, or certificates",
avoidable extras like a purchased domain or a paid DNS failover service,
both of which this project genuinely avoided (see the pricing comparison
in [requirement-5-multi-region-ha.md](requirement-5-multi-region-ha.md)).
Running compute for the actual Kubernetes cluster isn't in that
category. It's the thing being graded.

**Was there a cheaper VM size that could have worked instead?** Azure
calls a VM size a SKU (Stock Keeping Unit). Yes, and it was tried first:
`terraform/azure/variables.tf` already documents this. `Standard_B2s`
(2 vCPU, 4 GB memory) was the original choice specifically because it's
the smallest size that comfortably runs Kubernetes, chosen to keep cost
close to zero. Azure reported no available capacity for it on this
subscription, in either West Europe or North Europe, a real limitation
hit live during the build, not a preference. `Standard_D2s_v3` replaced
it: not the cheapest possible size, but a mainstream one with no
capacity restriction, and with more memory (8 GB instead of 4 GB) as a
side effect.

Checked against Azure's own published retail pricing for West Europe,
`Standard_B2s` is **$0.048 per hour** and `Standard_D2s_v3` is **$0.12
per hour**, two and a half times more expensive, not a marginal
difference. Had B2s actually been available, the real Azure total shown
above would likely have landed somewhere around €4 to €5 instead of
roughly €12, scaling down proportionally with the hourly rate. The gap
between the two isn't a design choice. It's the cost of a capacity
constraint that had no workaround on this specific subscription. What
*is* a design choice, and what kept even the D2s_v3 total this low, is
deallocating the VMs between build sessions rather than leaving them
running continuously.

### Requirement 5's traffic router, and a six-hour lesson in checking my own work

The same GCP (Google Cloud Platform) showcase VM also runs Requirement
5's actual traffic router: an NGINX reverse proxy, installed as a plain
systemd service, deliberately independent of the K3s cluster running
alongside it on the same machine. It sits in front of both Azure
regions, West Europe as the primary backend and Germany West Central as
a passive-health-checked backup. If West Europe stops answering,
NGINX's own `max_fails` / `fail_timeout` settings mark it down and start
sending traffic to Germany West Central instead, with no DNS change and
no manual step involved.

![The node ready, and the proxy's own IP already serving a 200 OK, moments before the proxy install began](docs/screenshots/63-gcp-showcase-ready-before-proxy-install.png)
*Above: All three `kubectl` contexts healthy, and a direct `curl` to the GCP
node's IP already returning `200 OK` from the NGINX that ships with a
fresh Ubuntu image: confirmed clean before the proxy role touched
anything.*

Installing that proxy turned into the longest single debugging session
of this whole build, close to six hours, across three separate but
related problems. It's documented in full because the actual lesson
(the third problem) is more valuable than the demo itself: a clean
architecture doesn't protect you from a sloppy operating habit.

**Problem 1: the install itself hung.** The Ansible run reached the
`Install NGINX` task and simply stopped producing output.

![ansible-playbook stuck at the Install NGINX task, no error, no progress](docs/screenshots/64-proxy-install-hung-on-nginx-task.png)
*Above: No error. The play just stopped advancing after this task started.*

`ps aux | grep -i apt`, run over a second SSH (Secure Shell) session
against the same node, found the actual cause: Ubuntu's own background
`update-notifier/apt-check` process, the thing that silently checks for
available package updates, sitting in Linux process state `D` (marked
`DN+` in the listing below). A `D`-state process is in *uninterruptible
sleep*: the kernel has it blocked on I/O (Input/Output, in this case
disk reads or writes) that hasn't completed yet, and **`kill -9` cannot
touch it**. `SIGKILL` is delivered to the process, not to the kernel
operation it's waiting on, so the process simply cannot respond to any
signal until that I/O either finishes or the machine reboots. This is
the same slow `pd-standard` (HDD) disk from the earlier I/O-wait
incident above, showing up in a new place. This time it wasn't K3s's
own database being slow, it was Ubuntu's routine update check, and it
happened to be holding the exact same `apt`/`dpkg` package-manager lock
that `apt-get install nginx` also needed.

![apt-check caught in D-state, unkillable, holding the apt lock](docs/screenshots/65-apt-check-stuck-in-d-state.png)
*Above: `DN+` in the `STAT` column: uninterruptible sleep. This process cannot
be killed. Only a reboot, or the I/O finally completing on its own,
clears it.*

**Problem 2: the first fix wasn't the whole fix.** Masking the systemd
timers that normally trigger `apt-check` (`apt-daily.timer`,
`apt-daily-upgrade.timer`, `motd-news.timer`) and rebooting looked like
a complete fix. `systemctl disable --now` reported success, cleanly
removing each timer's symlink. But retrying the playbook stalled again,
this time even earlier, at `Gathering Facts`, before NGINX's own task
had even started. Something *other* than those three known timers was
still triggering the same slow-disk contention on every boot, most
likely a login-banner script or a `cloud-init` step running
independently of systemd's timer system. Rather than keep hunting for
that exact remaining trigger with the clock running, the fix that
actually shipped (`ansible/roles/proxy/tasks/main.yml`) goes one level
more direct: `chmod 0000` on `/usr/lib/update-notifier/apt-check`
itself, so the program cannot be executed *at all*, however it gets
called. Removing every permission from the binary makes the question
"what's still triggering it?" stop mattering.

![Timers masked and the retry launched, which stalled again anyway](docs/screenshots/66-timers-masked-retry-stalls-again.png)
*Above: The masking command succeeded (three timer symlinks removed), and the
retry got further into the play before stalling again: proof the first
fix was real but incomplete, not proof it had failed outright.*

**Problem 3: the actual root cause, and the one that mattered most.**
After the `chmod 0000` fix, the playbook was retried several more times
over the next hour without any of those retries clearly finishing or
clearly failing. Each one looked "stuck" in roughly the same place,
which looked at the time like the same disk problem recurring yet
again. It wasn't. Running `ps aux | grep ansible-playbook`, a check I
should have made standard *before* the very first retry and didn't,
showed two separate `ansible-playbook` processes running at once,
started thirteen minutes apart, both targeting the same node with
`--limit gcp-showcase`. Each retry had been launched without first
confirming the previous one had actually exited, and every one of those
overlapping processes was fighting the others for the exact same remote
`apt`/`dpkg` lock, manufacturing fresh contention on top of a disk that,
by this point, had already been fixed. Denis caught this himself,
correctly, mid-session: *"dont we first need to check that no other
ansible playbook is running? you keep making me run playbook but not
check thats how we ended up with three playbooks."* That's now a
standing rule for every retry going forward, on this project or any
other: check `ps aux | grep ansible-playbook` first, and `pkill -9 -f
ansible-playbook` to clear any leftover process, *before* launching
another one, not after the second or third hang.

![ps aux catching two overlapping ansible-playbook processes, thirteen minutes apart](docs/screenshots/67-duplicate-ansible-playbook-processes-found.png)
*Above: The actual root cause of most of this session's apparent "hanging":
`ps aux | grep -i apt` shows a clean node with nothing stuck. The real
problem was one command away, in `ps aux | grep ansible-playbook`.*

Once those duplicate processes were killed and the retry was launched
alone, the play ran straight through without a single further pause.

![The proxy role's full run, top to bottom, no interruption](docs/screenshots/68-proxy-install-clean-run-success.png)
*Above: `PLAY RECAP ... ok=22 changed=6 unreachable=0 failed=0`. The same role
that stalled for hours completed cleanly once it was only running
once.*

![NGINX, reached over HTTPS at the proxy's own address, serving West Europe's page through it](docs/screenshots/69-proxy-serving-west-eu-over-https.png)
*Above: `curl -sk https://136.115.185.153/`. The `-k` flag accepts the proxy's
own self-signed certificate, the same free, zero-dependency approach
used by `cert-manager` inside each K3s cluster, returning West Europe's
Hello World HTML, proxied end to end over TLS.*

The honest read on the six hours: the first two problems were real and
worth documenting (a slow Always-Free disk can wedge an unrelated apt
install through nothing more exotic than an OS's own background update
checker), but they were solved within the first ninety minutes. The
other four-plus hours were spent fighting a problem I had personally
caused by retrying without checking, a reminder that in operations
work, an unverified assumption ("that process must have exited by now")
costs far more time than the two seconds it takes to actually check.

## Screenshots

90 screenshots live in [`docs/screenshots/`](docs/screenshots/),
numbered in build order and referenced throughout this document. Every
one of them is real output from this actual build, not a mockup. Rather
than duplicate that navigation here, see the
[Map](#map-jump-straight-to-what-you-need) at the top for the fastest
way to find a specific one, by requirement or by incident.

- [x] Requirements 1-5: all live, all demoed, all screenshotted
- [x] Requirements 6-8: written concept docs, each with real supporting
      evidence rather than staged examples. See
      [`requirement-6-monitoring-concept.md`](requirement-6-monitoring-concept.md),
      [`requirement-7-backup-recovery-concept.md`](requirement-7-backup-recovery-concept.md),
      [`requirement-8-dns-debug-runbook.md`](requirement-8-dns-debug-runbook.md)
- [x] Every real incident hit during the build, kept in rather than
      edited out. See the incidents table in the Map
- [x] The cost claim checked against real billing data, not just
      asserted

## How this is being built

Every piece of infrastructure code has its own explanatory comments
written directly alongside it, so the reasoning for a decision lives
right next to the decision itself.
[docs/cli-output-recap-reminder.md](docs/cli-output-recap-reminder.md)
explains the recurring tool output shown throughout this document, the
Ansible, Terraform, and kubectl fields that appear in screenshot after
screenshot, field by field.

## Author

Denis Riungu, [LinkedIn](https://linkedin.com/in/denis-riungu)
