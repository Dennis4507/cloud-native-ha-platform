# Requirement 1 — Kubernetes cluster

> CGI's brief: *"Deploy a K8s cluster... using any provisioner... To
> automate the deployment, Infrastructure as Code (IaC), a script, or a
> playbook should be used. The local machine of the challenge participant
> should be able to connect to the cluster using kubectl, and 'kubectl get
> nodes' should return at least two nodes with the status 'Ready.'"*
>
> [Verify against the full brief →](CGI-Challenge-Brief.md#requirement-1)

**In short:** two independent Kubernetes clusters, one per Azure region,
built entirely through Terraform and Ansible — no manual clicking.
Verified live with `kubectl get nodes`, run from my own laptop.

## What I built

**Two identical Kubernetes clusters** — one in Azure's West Europe
region, one in Germany West Central. Both built entirely through code, no
manual clicking in the Azure Portal.

- **Terraform** creates the infrastructure: a resource group, a virtual
  network per region, a Network Security Group (Azure's firewall), a Load
  Balancer, and a Virtual Machine Scale Set (VMSS) per region.
- **A VMSS** manages a group of identical VMs as one resource — it scales
  the count, replaces unhealthy instances, and applies updates across all
  of them together. I chose it because Requirement 1 needs at least two
  real nodes per region, and Requirement 3 later needs them provably
  separate.
- **Ansible** configures what runs on top: disabling swap, enabling the
  kernel modules Kubernetes networking needs, then installing **K3s** — a
  lightweight Kubernetes distribution — as the control plane on one
  machine per region, joining the second as a worker.
- **Every VM accepts SSH key login only, never a password.** No password
  means nothing for an attacker to brute-force.

**The topology, stated plainly:** each region has **2 nodes**, running
K3s directly on the VM's operating system — K3s *is* the cluster
software, not something that runs inside it. The application itself
(Hello World, covered under Requirement 3) runs as **pods on top of**
those 2 nodes — starting at 2 pods per region and scaling up to 6 under
load, since there are still only 2 physical nodes underneath.

## Why not Azure's managed services?

Two separate decisions, easy to blur together, so worth stating
separately and precisely.

**Why not AKS (Azure Kubernetes Service, Azure's managed Kubernetes)
instead of self-managed K3s?** The real reason: **Requirement 8 was
planned as a live demo** — actually running `tcpdump` and inspecting
`iptables` rules on a real node in front of the panel, not just
describing the method. AKS worker nodes don't get a public IP by
default, so there's no direct network path to SSH into one — reaching it
normally needs a bastion host, a VPN, or Microsoft's own `kubectl debug
node` command (a temporary debug pod, not a direct shell), instead of a
plain SSH session. Self-managed K3s on a plain VM gives that access
directly, with a normal SSH key and no extra infrastructure to set up
mid-demo.

**Why not Azure Traffic Manager for multi-region traffic routing
(Requirement 5), instead of a self-hosted proxy?** Simply **cost**.
Traffic Manager is not part of Azure's free tier — it charges a base
monthly fee plus a charge per health-check query, running continuously
for as long as the profile exists. The brief is explicit: no money spent
on infrastructure services. A self-hosted NGINX reverse proxy does the
same job — routing traffic to whichever region is healthy — for zero
ongoing cost, and the brief itself names "a proxy-server as loadbalancer"
as an equally valid option to a managed PaaS service.

## Live demo

```bash
kubectl --context azure-west get nodes
kubectl --context azure-germany-west get nodes
```

![Both clusters, reached directly from my own laptop](docs/screenshots/33-kubectl-both-clusters-ready-from-laptop.png)
*Both regions showing two `Ready` nodes, run from my own laptop — exactly
what the requirement asks for.*

---

## Incidents along the way

Real problems hit and fixed during this build.

**⚠️ The cheapest VM size had no capacity.**
The original choice, `Standard_B2s`, was rejected twice — first for
insufficient local storage, then entirely, with Azure reporting zero
available capacity for it anywhere on this subscription.

![Both regions rejecting Standard_B2s at once](docs/screenshots/15-sku-not-available-error.png)

I checked this directly against Azure's own SKU catalog API instead of
guessing. The whole original region turned out to be restricted,
regardless of VM size. Fix: `Standard_D2s_v3`, and Germany West Central
instead — verified with a disposable test VM before touching anything
real.

![D2s_v3 confirmed working, before committing the real build to it](docs/screenshots/17-d2sv3-confirmed-germany-west.png)

**⚠️ Azure quietly replaced two VMs mid-session.**
Two machines started timing out during SSH testing. The cause: a
self-healing feature I'd built, `automatic_instance_repair`, replacing
any instance that failed the Load Balancer's health check — a check
watching port 80, where nothing was listening yet since the app wasn't
deployed. Azure had already silently swapped two machines for new ones.
Fix: disabled the feature until there's actually something on port 80 to
check.

**⚠️ Joining a worker node took three separate rounds to fix.**
The join step just hung, no error at all.

1. **Round one:** the firewall only allowed the Kubernetes API port from
   my own laptop, not from the other VM in the same region. Added the
   missing rule.
2. **Round two:** `kubectl get nodes` still showed only one node per
   region. The first hung attempt had partially installed Kubernetes, so
   the retry saw "already installed" and skipped the step — even though
   nothing had actually joined. Fix: check whether the service is truly
   *running*, not just present.
3. **Round three:** still failing. The worker was reaching its control
   plane's *public* address, and Azure didn't treat that as internal
   traffic even on a shared private network — so the earlier firewall
   rule never applied. Fix: point each worker at its control plane's
   *private* address instead.

![Both clusters, two Ready nodes each, confirmed from inside the cluster](docs/screenshots/28-both-clusters-ready.png)

**⚠️ `kubectl` worked from the server, not from my own laptop** — which
is specifically what the requirement asks for. Three problems stacked:

1. **A stale `kubectl` install** — version 1.16 from 2019, far too old to
   connect to a modern cluster. Fixed with a clean reinstall.
2. **A merge script writing to the wrong place.** It reported success,
   but only one generic context appeared. Cause: a leftover
   `$KUBECONFIG` environment variable pointing at an unrelated file, from
   also running `kubectl` on Windows directly. The script was writing
   correctly — nothing was reading from where it wrote.
3. **A TLS certificate error.** K3s generates its API certificate once,
   at first boot, listing only the addresses it knows about at that
   instant — never the public IP Azure assigns from outside the machine.
   Fixed with `--tls-san <public-ip>` at install time, which meant a
   clean reinstall of the whole cluster, since the certificate can't be
   regenerated on a running node.

![Both clusters, reached directly from my own laptop - Requirement 1, done](docs/screenshots/33-kubectl-both-clusters-ready-from-laptop.png)
