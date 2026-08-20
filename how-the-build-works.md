# How this platform actually gets built

This file exists to answer one question, for every command in this whole
project: **what does this actually do, to which file, and why does it have
to happen here and not somewhere else?** It's written to be read cold, out
loud, in front of people who will ask follow-up questions - so every
acronym gets spelled out the first time it appears in this document, even
ones that already got explained elsewhere, since this file needs to stand
on its own.

This is also, deliberately, the raw material the actual presentation
script gets built from - the order these stages appear in below is the
order the whole demo should walk through too.

## The big picture, before any detail at all

Four stages, each one building on the last, nothing skippable or
reorderable:

1. **Terraform** builds the empty infrastructure - real servers, real
   networks, real firewalls - with nothing running on them yet.
2. **Ansible** turns those empty servers into a working Kubernetes
   cluster, and, on one specific machine, a traffic router too.
3. **Git and ArgoCD** get the actual application running on top of that
   cluster - not by typing a command by hand, by ArgoCD continuously
   watching a Git repository and matching the cluster to it.
4. **A small set of verification commands** - `kubectl`, `curl`, k6, k9s -
   prove each requirement is actually true, live, rather than just
   claimed.

Everything below walks through each of those four stages in detail: the
exact command, chopped into its individual pieces; the real file that
command reads; and a walkthrough of what happens to each part of that file
once the command actually runs.

## Stage 0 - Before Terraform can even start: somewhere to remember what it built

Terraform needs a place to store its own memory of what it has already
created - called its **state**. That storage has to exist *before*
Terraform's very first run, which is why this is a separate, one-time
script rather than something Terraform manages itself.

**The command:**
```bash
bash scripts/bootstrap-tfstate.sh
```
- `bash` - runs the script using the Bash shell specifically, rather than
  whatever the system default happens to be.
- `scripts/bootstrap-tfstate.sh` - the actual file being run.

**The file it runs, `scripts/bootstrap-tfstate.sh` (the parts that matter):**
```bash
RESOURCE_GROUP="rg-tfstate"
LOCATION="westeurope"
CONTAINER_NAME="tfstate"
BACKEND_CONFIG_FILE="terraform/azure/backend-config.hcl"

az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}"

az storage account create \
  --name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --sku Standard_LRS \
  --allow-shared-key-access false

az storage account blob-service-properties update \
  --account-name "${STORAGE_ACCOUNT}" \
  --enable-versioning true

az storage container create \
  --name "${CONTAINER_NAME}" \
  --account-name "${STORAGE_ACCOUNT}" \
  --auth-mode login
```

**What actually happens, line by line:** the script first creates its own
Azure Resource Group (`rg-tfstate`) - deliberately a *different* one from
`rg-ha-platform`, the group Terraform will go on to manage, so that a
future `terraform destroy` of the real platform can never accidentally
wipe out the very record of what needs destroying. Then it creates one
Storage Account inside that group - with `--allow-shared-key-access
false`, meaning there is no password-like access key for this storage at
all; every reader, Terraform included, has to authenticate as a real,
named identity instead. Blob versioning gets switched on next, so that if
a future Terraform run is interrupted mid-write and corrupts the state
file, the previous good version is still recoverable. Finally it creates
the Container - the actual folder-like space inside that storage account
where the state file (`azure.tfstate`) will live - and writes out
`terraform/azure/backend-config.hcl`, a small file recording exactly which
storage account and container Terraform should point at. That file is
gitignored on purpose: the storage account name is unique to this one
Azure subscription and would break `terraform init` for anyone else.

**What it proves:** nothing user-visible by itself - this is pure
groundwork. Everything from Stage 1 onward depends on this having already
happened once.

## Stage 1 - Terraform builds Azure's empty infrastructure

**The command, chopped up:**
```bash
terraform init -backend-config=backend-config.hcl
terraform plan
terraform apply
```
- `terraform` - the tool itself.
- `init` - reads `providers.tf` and `backend.tf`, downloads the Azure
  provider plugin (the actual code that knows how to speak to Azure's
  API), and connects to the state storage Stage 0 just created.
- `-backend-config=backend-config.hcl` - tells `init` exactly which
  storage account/container to use, from the file Stage 0 wrote.
- `plan` - works out what *would* change, without changing anything yet -
  a dry run.
- `apply` - actually creates the real resources.

**The file it locates, `terraform/azure/main.tf` - the actual resource
blocks it contains:**
```hcl
resource "azurerm_resource_group" "main" { ... }

resource "azurerm_virtual_network" "this" { ... }
resource "azurerm_subnet" "vmss" { ... }

resource "azurerm_network_security_group" "this" {
  security_rule { name = "AllowSSHFromAdmin" ... }
  security_rule { name = "AllowK3sAPIFromAdmin" ... }
  security_rule { name = "AllowHTTPFromAnywhere" ... }
  security_rule { name = "AllowHTTPSFromAnywhere" ... }
}

resource "azurerm_user_assigned_identity" "main" { ... }

resource "azurerm_public_ip" "lb" { ... }
resource "azurerm_lb" "this" { ... }
resource "azurerm_lb_backend_address_pool" "this" { ... }
resource "azurerm_lb_probe" "http" { ... }
resource "azurerm_lb_rule" "http" { ... }
resource "azurerm_lb_rule" "https" { ... }

resource "azurerm_linux_virtual_machine_scale_set" "this" { ... }
```
Every block here that names a region uses Terraform's `for_each` - one
set of code, run twice, once per region (West Europe, Germany West
Central), rather than the whole file being duplicated.

**What actually happens, block by block, when `apply` runs:** Terraform
reads the file top to bottom, works out the *dependency order* between
blocks automatically (it knows the Virtual Network has to exist before a
Subnet can reference it, for example, without being told explicitly), and
creates each real Azure resource in that order. `azurerm_resource_group`
becomes the container everything else lives inside. `azurerm_virtual_network`
and `azurerm_subnet` become each region's own private network.
`azurerm_network_security_group` becomes the firewall - SSH (Secure
Shell, the encrypted way to log into a machine's command line) and the
Kubernetes API port restricted to `var.admin_source_ip` specifically,
HTTP and HTTPS (the encrypted version of the web, "Transport Layer
Security" underneath it) opened to genuinely anyone, since that's the
actual public entry point for the demo. `azurerm_user_assigned_identity`
becomes the VM's own identity for talking to Azure's APIs - no password,
no key file. The `azurerm_lb*` blocks together become the Load Balancer
each region's traffic actually arrives through, plus the health check
deciding which instances behind it are currently allowed to receive
traffic. And `azurerm_linux_virtual_machine_scale_set` becomes the actual
servers - two per region, Ubuntu, nothing installed on them yet beyond the
bare operating system.

**What it proves:** the *Infrastructure as Code* half of Requirement 1 -
that this cluster is built by a repeatable script, not clicked together by
hand in a web console.

## Stage 2 - Terraform builds GCP's empty infrastructure

Same tool, same pattern, a different cloud - GCP (Google Cloud Platform)
- entirely on purpose, to prove the same approach isn't Azure-specific.

**The command, chopped up:**
```bash
terraform init -backend-config=../azure/backend-config.hcl -backend-config="key=gcp.tfstate"
terraform apply
```
- Same `init`/`apply` as Stage 1.
- `-backend-config=../azure/backend-config.hcl` - reuses the *exact same*
  Azure storage account already built in Stage 0, rather than setting up
  a second, GCP-native backend just for one small VM's state.
- `-backend-config="key=gcp.tfstate"` - overrides just the filename
  Terraform writes state to *within* that shared storage account, so
  GCP's state and Azure's state never collide.

**The file it locates, `terraform/gcp/main.tf` - the actual resource
blocks:**
```hcl
resource "google_compute_network" "main" { ... }
resource "google_compute_subnetwork" "main" { ... }

resource "google_compute_firewall" "ssh" { ... }
resource "google_compute_firewall" "k3s_api" { ... }
resource "google_compute_firewall" "proxy_http" { ... }

resource "google_service_account" "gcp_showcase" { ... }

resource "google_compute_address" "static_ip" { ... }
resource "google_compute_instance" "gcp_showcase" { ... }
```

**What actually happens:** `google_compute_network` and
`google_compute_subnetwork` become this VM's own private network,
deliberately separate from GCP's automatically-created "default" network
every new project gets. The three `google_compute_firewall` blocks become
GCP's equivalent of Azure's NSG (Network Security Group) - except GCP
attaches firewall rules to the network itself, matched by a **tag** on
each instance, rather than per-subnet the way Azure does it: SSH and the
K3s API restricted to `var.admin_source_ip`, but HTTP/HTTPS opened to
*everyone*, since this one machine also ends up hosting Requirement 5's
public-facing proxy. `google_service_account` becomes this VM's identity
for GCP's own APIs - the same "no key file, no password" idea as Azure's
Managed Identity, just GCP's own version of it. `google_compute_address`
reserves a static IP that won't change if the VM is ever rebuilt, and
`google_compute_instance` becomes the actual VM - specifically an
`e2-micro`, in `us-central1`, because that's the exact size and region
combination GCP's Always Free tier actually covers; anything bigger, or
in a different region, would mean real, ongoing cost.

**What it proves:** cherry #2 - that the *same* Infrastructure as Code
approach genuinely works on a second, unrelated cloud provider, not just
the one it was first built on.

## Stage 3 - Ansible turns the empty servers into a working cluster

**The command, chopped up:**
```bash
ansible-playbook -i inventory/hosts.yml playbook.yml
```
- `ansible-playbook` - the tool that runs a whole ordered set of
  instructions across many machines at once, as opposed to `ansible`
  alone, which only runs one single ad-hoc command.
- `-i inventory/hosts.yml` - tells it which **inventory** to use: the
  file listing every machine that exists and which named groups each one
  belongs to (`k3s_server`, `k3s_agent`, `proxy_servers`).
- `playbook.yml` - the actual file being executed.

**The file it runs, `ansible/playbook.yml`, in full:**
```yaml
- name: Prepare every node the same way, regardless of cloud or role
  hosts: all
  become: true
  roles:
    - common

- name: Turn one machine per region into a Kubernetes control plane
  hosts: k3s_server
  become: true
  roles:
    - k3s-server

- name: Join the second machine per region as a worker
  hosts: k3s_agent
  become: true
  roles:
    - k3s-agent

- name: Install Requirement 5's traffic router
  hosts: proxy_servers
  become: true
  roles:
    - proxy
```

**What actually happens, top to bottom:** four **plays**, run strictly in
the order they're written - never in parallel, never rearranged. **Play
1** (`hosts: all`) resolves to every machine in the inventory - all five -
and runs `roles/common/tasks/main.yml` on each, as root (`become: true`
means every task runs via `sudo`). **Play 2** (`hosts: k3s_server`)
narrows to the three machines in that specific group and runs
`roles/k3s-server/tasks/main.yml`, installing K3s (a lightweight
Kubernetes distribution) in server mode. This has to finish before Play 3,
since Play 3's machines need a real, already-running server to join.
**Play 3** (`hosts: k3s_agent`) runs `roles/k3s-agent/tasks/main.yml` on
the two worker machines, using the join token Play 2 generated - passed
between plays through Ansible's own in-memory facts, never written to a
file. **Play 4** (`hosts: proxy_servers`) is just the GCP machine again,
but a completely different role - installing NGINX, not Kubernetes -
placed last because it's a separate concern layered on top of an
already-working cluster, not something the earlier plays actually depend
on existing first.

### What each role actually does, once its play reaches it

**`common` - `ansible/roles/common/tasks/main.yml`:**
```yaml
- name: Disable swap immediately
  command: swapoff -a

- name: Load the br_netfilter kernel module
  modprobe:
    name: br_netfilter
    state: present

- name: Apply the kernel network settings Kubernetes needs
  sysctl:
    name: "{{ item }}"
    value: "1"
  loop:
    - net.bridge.bridge-nf-call-iptables
    - net.ipv4.ip_forward
```
`swapoff -a` turns off swap (using disk space as overflow memory)
immediately - Kubernetes assumes it can trust the operating system's own
memory-pressure signals, and swap defeats that assumption by making an
overloaded machine look like it still has room to spare. `br_netfilter` is
a kernel module that lets the Linux network bridge hand traffic to
`iptables` (the Linux firewall/routing rule engine) at all - without it,
Kubernetes' own NetworkPolicy rules would silently stop applying, with no
obvious error pointing at the real cause. The two `sysctl` settings turn
that bridging on for real, and let this machine route packets between
pods running on *different* nodes - without `ip_forward`, a pod on one
node could never reach a pod on another.

**`k3s-server` - `ansible/roles/k3s-server/tasks/main.yml` (the install step):**
```yaml
- name: Install K3s in server mode
  shell: curl -sfL https://get.k3s.io | sh -s - --tls-san {{ ansible_host }} {{ k3s_server_extra_args | default('') }}
```
`curl -sfL https://get.k3s.io | sh -s -` downloads and runs K3s's own
official install script directly - the same "trust the upstream
installer" reasoning used throughout this project rather than hand-rolling
a Kubernetes install. `--tls-san {{ ansible_host }}` tells K3s to issue
its own certificate (the credential proving "this really is the real API
server") covering this machine's public IP specifically - without it, the
certificate only covers the private IP and localhost, which is exactly
why `kubectl` from outside the cluster would otherwise fail with a
certificate error. `{{ k3s_server_extra_args }}` is empty on both Azure
servers, but set to `--disable traefik --disable servicelb` specifically
for the GCP showcase - switching off two components that machine's disk
couldn't keep up with, since it never runs anything that needs either one
anyway.

**`k3s-agent` - `ansible/roles/k3s-agent/tasks/main.yml` (the join step):**
```yaml
- name: Join this machine to its region's K3s server as an agent
  shell: curl -sfL https://get.k3s.io | sh -
  environment:
    K3S_URL: "https://{{ hostvars[k3s_server_host]['ansible_default_ipv4']['address'] }}:6443"
    K3S_TOKEN: "{{ hostvars[k3s_server_host]['node_token'] }}"
```
The same install script as the server role, but two environment variables
switch its behavior from "become a new server" to "join an existing one."
`K3S_URL` points at the server's **private** IP address specifically, not
its public one - reaching it over the public internet, even between two
machines in the same project, doesn't count as "internal" traffic to
Azure's firewall, which is exactly the mistake this was originally built
to avoid. `K3S_TOKEN` is the join token Play 2 already read into memory,
proving this agent is allowed into this specific cluster and no other.

**`proxy` - `ansible/roles/proxy/tasks/main.yml` (the install step):**
```yaml
- name: Install NGINX
  apt:
    name: nginx
    state: present

- name: Generate a self-signed certificate for the proxy itself
  command: >
    openssl req -x509 -nodes -days 365 -newkey rsa:2048
    -keyout /etc/nginx/ssl/proxy-selfsigned.key
    -out /etc/nginx/ssl/proxy-selfsigned.crt
    -subj "/CN={{ ansible_host }}"

- name: Deploy the actual proxy configuration
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
```
`apt: name: nginx` installs NGINX as a normal system package - not a
container, not a Kubernetes workload, deliberately independent of the K3s
cluster running alongside it on the same machine. The `openssl` command
generates this proxy's own TLS certificate - self-signed, the same
"free, no domain needed, explicitly allowed by the brief" reasoning as
every certificate elsewhere in this project. The `template` task writes
the real configuration file (covered in Stage 5 below) from a template
that fills in the two regions' real IP addresses.

**What it proves:** the rest of Requirement 1 (`kubectl get nodes`
actually returning `Ready`), plus the infrastructure Requirement 5's
failover depends on - though not Requirement 5 itself yet, since nothing
has actually routed any traffic at this point.

## Stage 4 - Getting `kubectl` itself to reach any of this

**The command:**
```bash
bash scripts/kubeconfig-merge.sh
```

**What it does:** K3s writes its own kubeconfig (the file `kubectl`
reads to know which cluster to talk to, and with what credentials)
assuming it will only ever be read *from the server itself* - it points
at `127.0.0.1` and calls everything `default`. This script rewrites each
of the three servers' kubeconfigs to point at their real public IP
instead, renames each one's entries to a region-specific name
(`azure-west`, `azure-germany-west`, `gcp-showcase`), and merges all three
into one file - written to wherever `kubectl` actually reads from on this
laptop, with three separate, switchable **contexts**.

**What it proves:** the literal wording of Requirement 1 - that "the
challenge participant's own machine" can run `kubectl get nodes` directly,
not just from inside the cluster over SSH.

## Stage 5 - Git and ArgoCD deploy the actual application

This is the one stage that genuinely runs differently from all the others
- nobody types a deploy command by hand. ArgoCD (a GitOps tool - "GitOps"
meaning a Git repository is treated as the single source of truth for
what should be running, with a tool continuously reconciling the cluster
to match it) does the actual deploying, on its own, by watching this
project's GitHub repository.

**The one-time setup command:**
```bash
kubectl --context azure-west apply -f k8s/argocd/application-west-eu.yaml
```

**The file it applies, `k8s/argocd/application-west-eu.yaml`:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hello-world-west-eu
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/Dennis4507/cloud-native-ha-platform.git
    path: k8s/apps/hello-world/overlays/west-eu
  destination:
    server: https://kubernetes.default.svc
    namespace: hello-world
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```
`kubectl apply` here isn't deploying Hello World directly - it's creating
one `Application` object, which is ArgoCD's own custom resource type,
telling ArgoCD *what to watch and where to put it*. `repoURL` and `path`
are the actual instructions: watch this GitHub repository, specifically
the `k8s/apps/hello-world/overlays/west-eu` folder inside it.
`destination.server: https://kubernetes.default.svc` is a fixed address
meaning "the same cluster ArgoCD itself is running on" - no separate
cluster registration needed for this one, unlike Germany West Central's
matching file, which points at that region's real API address instead.
`syncPolicy.automated` with `selfHeal: true` is what makes this genuinely
different from a one-off deploy: if anyone (or anything) changes the
cluster by hand afterward, bypassing Git, ArgoCD reverts it back to match
Git automatically, on its own next check.

**The ongoing "command" - which isn't typed by a person at all:**
```bash
git push
```
Once the `Application` object above exists, this is the only thing that
actually causes a deployment from that point forward. ArgoCD polls the
repository on its own schedule (every few minutes by default), notices
the new commit, and syncs the cluster to match it - or, during active
development, `argocd app sync` forces that same check to happen
immediately instead of waiting.

**What it locates once it syncs, `k8s/apps/hello-world/overlays/west-eu/`:**
a Kustomize overlay (Kustomize being a tool for layering small,
region-specific changes on top of one shared base, instead of maintaining
several near-duplicate copies of the same files) - referencing the shared
`base/` folder (Deployment, Service, HPA, Ingress, self-signed
`ClusterIssuer`) plus this region's own `configmap.yaml` (the actual
"Hello World" text) and `certificate.yaml` (a request for a certificate
covering this region's specific public IP).

**What it proves:** Requirements 2 and 4 (Hello World, reachable over
HTTPS with a real certificate), and the GitOps cherry - that deployment
happens by pushing to Git, not by running a command against the cluster
directly.

## Stage 6 - Verification: proving each requirement live, not just claiming it

These commands don't map to a single file the way the earlier stages do -
each one is a direct test against the running system, and each one maps
to a specific requirement instead.

- **`kubectl --context azure-west get nodes`** - Requirement 1. Reads
  nothing but the live cluster's own current state; proves the nodes
  Stage 3 built are actually `Ready`.
- **A browser, `https://20.229.108.8/`** - Requirements 2 and 4. Proves
  Hello World is reachable, and that the certificate presented is the
  real one Stage 5's `certificate.yaml` requested, not a fallback.
- **`k6 run scripts/load-test.js`, watched in `k9s`** - Requirement 3.
  Genuine load against the real endpoint, proving the HPA (the controller
  from Stage 5's base manifests) actually adds replicas in response to
  real measured CPU usage, not a staged number.
- **Repeated `curl` against the Service's internal address** - the other
  half of Requirement 3, showing responses alternate between pods on
  different nodes.
- **Breaking West Europe's health check, watching the NGINX proxy (Stage
  3's `proxy` role) switch to Germany West Central, watched live in
  Uptime Kuma** - Requirement 5, the actual failover.
