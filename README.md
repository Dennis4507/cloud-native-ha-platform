# cloud-native-ha-platform

**By Denis Riungu**

## What this is

This project is my submission for CGI's Cloud & DevOps Challenge. The brief
asks for a Kubernetes platform that can survive real failures - a single
server dying, a whole cluster going down, an entire region becoming
unreachable - and asks that it all be built through code rather than by
clicking things together by hand.

I built two identical Kubernetes clusters, one in Azure's West Europe region
and one in Germany West Central, using Terraform to create the infrastructure and
Ansible to configure it. A small web application runs on both, spread across
multiple servers so that losing one server never takes the application down.
If an entire region fails, traffic automatically moves to the other one. On
top of that core, I added two extras that go beyond what the challenge
strictly asks for: the same automation pattern applied to a server on Google
Cloud, and a GitOps pipeline so that deployments happen by pushing to Git
rather than by running commands by hand.

## The 8 requirements this answers

| # | What was asked | How it's answered |
|---|---|---|
| 1 | A Kubernetes cluster, built through code | Terraform provisions the servers, Ansible installs Kubernetes on them |
| 2 | A simple "Hello World" web page, reachable in a browser | A small web server, deployed to the cluster |
| 3 | Traffic spread across multiple servers, scaling automatically under load | The application runs on 2+ servers at once, and adds more automatically when busy |
| 4 | Encrypted traffic (HTTPS) with a valid certificate | A certificate is issued automatically inside the cluster |
| 5 | The platform keeps working if an entire region fails | A second, independent cluster in a different region, with automatic traffic failover |
| 6 | A plan for monitoring the platform's health | Described in `docs/monitoring-concept.md`, plus a small live dashboard |
| 7 | A plan for backing up and recovering the platform | Described in `docs/backup-recovery-concept.md` |
| 8 | A method for diagnosing DNS problems on a server | A written, rehearsed troubleshooting process |

## Keeping this project isolated from everything else

CGI's own challenge brief offers a sandbox Azure environment on request, but
with a tight four-day window and a full schedule, there wasn't time to wait
on that request being fulfilled. Rather than build directly on a personal
account with other work in it, I provisioned my own equivalent sandbox:
before touching any real infrastructure, the Azure side was set up so that
this project can never accidentally reach - or be reached by - anything else
in the same account. The root account only ever acted as the administrator
who set this boundary up once; a second, deliberately limited identity
(`CGI Challenge Sandbox`) does all of the actual work from here on, and its
access is restricted to exactly the two resource groups this project uses.

![Resource groups, isolated from other work](docs/screenshots/01-resource-group-isolation.png)
*The two resource groups this project owns, sitting alongside an unrelated
resource group already in the account - proof this project has its own
clean space, not a shared one.*

![Two identities: administrator and sandbox](docs/screenshots/02-entra-sandbox-identity.png)
*Two separate identities in the same account: the administrator account that
set everything up, and the sandbox identity that actually builds the
challenge.*

![Scoped permissions, not full access](docs/screenshots/03-rbac-scoped-roles.png)
*The actual access breakdown on the Terraform state resource group: the
administrator holds full ownership, while the sandbox identity holds only
the specific permissions it needs to do its job - and, importantly, no
permission to grant access to anyone else, including itself.*

![The sandbox identity's own view](docs/screenshots/04-sandbox-own-view.png)
*Signed in as the sandbox identity itself: this is the whole world it can
see - exactly the two resource groups this project owns, and nothing else.*

One consequence of creating these resource groups by hand, before Terraform
ever ran: Terraform didn't know they already existed, and refused to quietly
create a duplicate on top of them - the correct, safe behavior. The fix was
`terraform import`, a standard way to bring an already-existing resource
under Terraform's management instead of recreating it. Worth knowing that a
resource group's own region is just metadata about where its record lives;
it doesn't control where the resources inside it actually get created, so
this had no effect on the real regional design (see below for how that
design itself later changed).

![Terraform correctly refusing to duplicate an existing resource](docs/screenshots/11-apply-rg-conflict.png)
*Terraform noticing the resource group already exists and stopping, rather
than silently creating a conflicting duplicate.*

![Import successful](docs/screenshots/12-import-successful.png)
*The fix: bringing the existing resource group under Terraform's management
with `terraform import`, rather than recreating it. Personal details in the
scrollback (IP address, SSH key) are manually blacked out.*

## Where things stand right now

This project is being built in small, deliberate steps rather than all at
once, so this section will keep changing as it goes. As of today: all of
the Azure infrastructure is live in the real subscription - the network,
firewall, load balancers, identity, and both regions' virtual machine
scale sets, four servers total, two in West Europe and two in Germany West
Central. That's Requirement 1's actual infrastructure done. The next step
is installing Kubernetes on these servers with Ansible, then confirming
`kubectl get nodes` shows all of them Ready.

![The state storage being created](docs/screenshots/05-bootstrap-tfstate-done.png)
*The one-time setup script creating the dedicated Azure storage that will
hold Terraform's record of everything it builds.*

![Terraform successfully initialized](docs/screenshots/06-terraform-init-success.png)
*Terraform confirming it can reach that storage and is ready to start
managing real infrastructure.*

![Terraform plan, fully validated](docs/screenshots/07-terraform-plan-clean.png)
*The complete infrastructure plan, validated end to end: 22 resources ready
to create, nothing changed or destroyed - the network, firewall, load
balancers, identity, and both regions' virtual machines, all matching the
design exactly.*

![The rule keeping state out of Git](docs/screenshots/08-gitignore-protects-state.png)
*The actual rule that keeps Terraform's state, and anything else sensitive,
out of version control entirely - not a claim, the real configuration.*

![The state storage container in Azure](docs/screenshots/09-state-storage-account.png)
*Inside that storage account: the `tfstate` container, sitting there in the
Azure Portal - proof this is a real, working remote backend, not just files
on a laptop.*

**The virtual machines Terraform is about to create only accept login by SSH
("Secure Shell," the encrypted way to log into a remote machine's command
line) key, never a password** - that was a deliberate security choice made back
when this infrastructure was first designed, since no password means there
is nothing for an attacker to brute-force. The public key is what gets
uploaded to Azure and installed on the machines; the matching private key,
which never leaves this computer, is what actually proves it's really me
when I connect later.

A second tradeoff surfaced the same way, once real virtual machines were
actually attempted: the original design used an "ephemeral" OS ("Operating
System") disk, which stores the operating system on the virtual machine's
own local storage
instead of over the network. It boots noticeably faster and costs nothing
extra, since it reuses space already included in the machine's price - but
it only works if the operating system image is small enough to fit in that
local space. `Standard_B2s` (chosen specifically to keep this project's cost
near zero) only has 8 GB of local storage, and the Ubuntu image needed more
room than that. Azure rejected it outright the moment the virtual machines
were actually created, rather than at any earlier check:

![Azure rejecting the ephemeral disk on this VM size](docs/screenshots/13-ephemeral-disk-error.png)
*19 of the 21 resources succeeded before this - the network, firewall,
load balancers, and identity were all unaffected. Only the two virtual
machine scale sets failed, both for the same reason.*

The fix was switching to a normal, network-attached managed disk instead -
a few cents a month, a slightly slower boot, but guaranteed to work on this
VM size. Boot speed was never part of the actual design or any of the 8
requirements, so this was a pragmatic call rather than a real setback: try
the faster option first, hit a genuine platform limit, adjust.

![The actual code change, before and after](docs/screenshots/14-ephemeral-disk-code-fix.png)
*Removing the ephemeral disk settings in favor of a plain managed disk - a
four-line change once the real limitation was understood.*

A third, more significant issue surfaced next: Azure refused to create
either virtual machine at all, in either region, reporting the requested
size as unavailable due to "capacity restrictions."

![Both regions rejecting the VM size at once](docs/screenshots/15-sku-not-available-error.png)
*Azure rejecting `Standard_B2s` in both West Europe and North Europe
simultaneously, each for the same reason: no available capacity for this
subscription.*

Rather than guess at a fix, this one was investigated directly against
Azure's own SKU ("Stock Keeping Unit" - Azure's term for a specific virtual
machine size, like `Standard_B2s`) catalog API ("Application Programming
Interface" - the interface a program uses to ask a service a question
directly, rather than through its web portal) - querying which virtual
machine sizes this specific subscription is actually allowed to use in
which regions.

![The SKU catalog confirming the restriction](docs/screenshots/16-sku-catalog-investigation.png)
*Azure's own catalog data: North Europe carries a `NotAvailableForSubscription`
restriction for this subscription, regardless of which VM size is chosen.*

The result was clear: North Europe is restricted for this subscription
across every size checked, not just the one originally chosen - the whole
region is closed off, unrelated to any setting in this project's code.
Germany West Central, by contrast, came back clean. Since the resource
group itself already lived in Germany West Central (from the isolation
setup earlier), and West Europe was unaffected, the fix was replacing North
Europe with Germany West Central as the second region, rather than hunting
for a differently-sized VM that might work in a region this subscription
can't actually use. Every resource name that said "north-eu" was also
renamed to "germany-west" at the same time, so nothing in the code claims
to be running somewhere it isn't.

Before changing the real infrastructure, that fix was verified cheaply
first: a single throwaway virtual machine, created directly (not through
Terraform) with the exact size the code now uses, in the exact region it
would now run in.

![Standard_D2s_v3 confirmed working in Germany West Central](docs/screenshots/17-d2sv3-confirmed-germany-west.png)
*The throwaway test VM, running - proof the fix actually works before
committing the real infrastructure to it. Deleted immediately after.*

With the region and VM size both confirmed, the real `terraform apply` ran
clean: the old North Europe network resources were destroyed automatically
(they were tied to a region this subscription can't use), and everything
was recreated in Germany West Central alongside West Europe.

![Terraform apply complete](docs/screenshots/18-apply-complete.png)
*`Apply complete! Resources: 11 added, 0 changed, 9 destroyed.` Both virtual
machine scale sets created successfully - this is Requirement 1's actual
infrastructure, live.*

![Both scale sets confirmed in the Azure Portal](docs/screenshots/19-vmss-succeeded-portal.png)
*`vmss-west-eu` and `vmss-germany-west`, both showing "Succeeded" - the same
result confirmed from the Azure side, not just the terminal.*

One deliberate distinction worth being explicit about: each virtual machine
also gets its own public IP address, added specifically so Ansible (and I)
can reach individual machines directly over SSH. That address is purely an
administrative access path - it has nothing to do with this platform's
actual availability design. If Azure ever replaces a broken instance
automatically, the replacement gets a brand-new public IP; the old one is
simply gone. The address real traffic (or the failover proxy) ever talks to
is the load balancer's frontend IP from Phase 1, which never changes
regardless of what happens to the instances behind it. Application
availability never depends on any single machine's address - only my own
SSH access does.

![Each instance's public IP, confirmed](docs/screenshots/20-instance-public-ips.png)
*All four machines, each with its own address - the exact IPs Ansible will
connect to next.*

![The Portal showing a single IP per scale set](docs/screenshots/21-lb-ip-vs-instance-ip.png)
*The Azure Portal's scale set overview shows only one IP per region -
`20.229.108.8` for West Europe, `20.218.111.44` for Germany West. That's not
a smaller number of real IPs; it's the load balancer's frontend address,
which is what that summary view is built to show. The screenshot above it
shows the other four addresses - two per region, one per virtual machine -
because that command asked specifically for instance-level IPs instead of
the scale set's own summary. Same infrastructure, two different views of it,
each showing exactly what it's designed to show.*

One more real incident worth including, because it's genuinely instructive
rather than just a mistake to fix quietly: while first testing whether
Ansible could reach all four machines over SSH, two of them - one per
region - consistently timed out, while the other two connected fine every
time. The cause turned out to be `automatic_instance_repair`, a feature
built back in Phase 1 specifically to replace any machine that fails the
load balancer's health check. That health check watches port 80 - but
nothing was listening on port 80 yet, since the actual application hadn't
been deployed. Every instance had been failing that check since the moment
it booted, and Azure had already quietly replaced two of them mid-session,
each with a brand-new public IP that no longer matched what was written in
the inventory. Confirmed directly: querying the scale sets showed each
"agent" instance now had a different address than the one originally
recorded.

This was real self-healing working exactly as designed - genuinely good
news - but actively disruptive while there's nothing meaningful for the
health check to measure yet. The fix was disabling `automatic_instance_repair`
for now, with a note to re-enable it once the Hello World app is actually
deployed and port 80 has something real behind it - not a permanent
decision, a sequencing one.

![The code fix, before and after](docs/screenshots/22-auto-repair-disabled-code-fix.png)
*Turning the feature off with a one-line change, applied in place with no
disruption to the machines already running.*

![The inventory updated with the real, current addresses](docs/screenshots/23-inventory-ip-updated.png)
*Both replaced addresses corrected in the Ansible inventory, with a note
explaining why they don't match the originally-assigned IPs.*

![All four machines reachable](docs/screenshots/24-ansible-ping-success.png)
*Every host responding `"ping": "pong"` - full connectivity confirmed,
after tracking down why two of the four addresses had silently changed.*

### Getting Kubernetes actually installed and joined

With all four machines reachable, the next step was installing Kubernetes
itself. The first part went smoothly: every machine got the same basic
setup, and one machine per region became the control plane without any
trouble. The second part - joining the other machine in each region to
that control plane as a worker - did not go smoothly, and it took three
separate rounds of digging to actually fix.

**Round one.** The join step just hung, with no error at all.

![The join step hanging with no error](docs/screenshots/25-k3s-join-hang.png)
*Nothing wrong reported - just silence, until it was interrupted by hand.*

It turned out the firewall only allowed the Kubernetes API port (6443) to
be reached from my own laptop, not from the other virtual machine in the
same region - which is exactly what a worker needs to do to join its
control plane. That rule was added and applied.

**Round two.** Running the setup again looked like it worked, but
`kubectl get nodes` still only showed one machine per region, not two. The
reason: the very first attempt had gotten far enough to download Kubernetes
before it hung, so the second attempt saw "it's already installed" and
skipped the step entirely - even though the machine had never actually
finished joining anything. The fix was checking whether the service was
truly running, not just whether the software was present.

![The fix: checking the real service state, not just the file](docs/screenshots/26-idempotency-check-fix.png)
*A more honest check - "is this actually working," not just "does the file
exist."*

**Round three.** Even with that fixed, the join still failed. This time,
checking directly from one machine to the other confirmed the real cause:
the worker was trying to reach its control plane's *public* internet
address, and even though both machines sit in the same private network,
Azure did not treat that connection as internal traffic - so the firewall
rule from round one never actually applied to it.

![Confirming the connection was still blocked](docs/screenshots/27-tcp-connection-blocked.png)
*A direct, one-line test settled it before guessing again.*

The real fix was pointing each worker at its control plane's private
address instead of its public one - which the firewall rule correctly
allows, and which is also simply the right way to do it: machines in the
same network talking to each other should use their private addresses, not
bounce out to the internet and back.

![Both clusters, two Ready nodes each](docs/screenshots/28-both-clusters-ready.png)
*The result: both regions show two `Ready` nodes - confirmed here from
inside each cluster, over SSH. Requirement 1's own wording asks for more
than that, though: it specifically wants this checked from the challenge
participant's own machine, not from a session on the server itself. That
turned out to still be one incident away.*

### Making `kubectl` itself work from my own laptop

Two clusters existing is not the same thing as being able to reach them.
Requirement 1 is specific about this: running `kubectl get nodes` from my
own machine, not from a terminal already sitting on one of the servers,
needs to show both `Ready` nodes. Getting there surfaced three separate
problems, stacked on top of each other.

The first was mundane: the `kubectl` already installed on this laptop
turned out to be version 1.16, from 2019 - untouched since long before this
project started. Kubernetes enforces a version-skew policy between client
and server, and a gap that large simply refuses to work. Fixed with the
official install script, which brought it up to 1.36 - the same version the
cluster itself runs.

The second was a merge script quietly writing to the wrong place. Ansible
already fetches each cluster's kubeconfig from its server, and
`scripts/kubeconfig-merge.sh` combines both into one file with two named
contexts. It ran without error, but `kubectl config get-contexts` afterward
showed only a single, generic `default` entry - as if the merge had never
happened at all.

![Merge reports success, but only one generic context exists](docs/screenshots/29-kubeconfig-context-not-found.png)
*The script's own messages all say "done" - the problem was invisible from
its output alone.*

Ruling things out one at a time is what found it. First the merge logic
itself - reproduced by hand, and it worked fine. Then line endings, the
first suspect - checked directly, and they were plain Unix `LF` ("Line
Feed" - a single character marking the end of a line), not the Windows
`CRLF` ("Carriage Return Line Feed" - Windows' two-character version of the
same thing) that would have caused this. That left one line: `echo
$KUBECONFIG`. This laptop already had that environment variable set,
pointing at a completely different file on the Windows side
(`/mnt/c/Users/OnlyM/.kube/config`) - left over from also running `kubectl`
straight from Windows, not just from WSL ("Windows Subsystem for Linux,"
the Ubuntu environment inside Windows this whole project actually runs
from). The script had been faithfully writing its merged result to the
plain default location, `~/.kube/config` - `kubectl` itself was just never
looking there. The fix: read `$KUBECONFIG` if it's already set, and only
fall back to the default when it isn't.

![The real cause, found, and the fix taking effect](docs/screenshots/30-kubeconfig-env-var-fix.png)
*`echo $KUBECONFIG` revealing the Windows-side path, then the script
re-run - both contexts now show up correctly. And immediately, a third,
different error appears underneath it.*

That third error was the real one: a certificate. Kubernetes' API server
encrypts every connection to it using TLS ("Transport Layer Security" - the
encryption behind `https://`), including connections from `kubectl` itself, and K3s
generates that certificate exactly once, the moment it first starts -
listing only the addresses it already knows about at that instant. Both
servers' certificates covered their private IP, the cluster's internal
service address, and localhost - never the public IP this laptop actually
connects through, because that address is assigned by Azure from outside
the machine, not something the operating system itself has any way to know
about at install time.

![Both regions rejecting the connection over TLS](docs/screenshots/31-tls-san-both-regions-error.png)
*Same shape of error on both clusters - each one naming its own private
address as valid, and the public one it was actually asked for as not.*

The fix was a single added argument at install time - `--tls-san
<public-ip>` - telling K3s to also issue the certificate for that address.
Because the certificate is only ever generated once, this only takes effect
on a fresh install, not a running one: both control-plane nodes needed a
clean uninstall, and since a fresh server also means a fresh join token,
both worker nodes needed to rejoin from nothing too. Confirmed clean on all
four machines first, then one full `ansible-playbook` run rebuilt the
entire platform from scratch - itself a small proof of the point of
automating any of this in the first place.

![All four nodes confirmed clean before rebuilding](docs/screenshots/32-k3s-clean-uninstall-confirmed.png)
*Neither the `k3s` binary nor its systemd service exist anymore on any of
the four machines - a clean slate, not a half-removed one.*

![Both clusters, reached directly from my own laptop](docs/screenshots/33-kubectl-both-clusters-ready-from-laptop.png)
*The rebuild, the kubeconfig merge, and both `kubectl --context ... get
nodes` calls - run from this laptop, not over SSH, exactly as Requirement 1
asks for it. Both regions show two `Ready` nodes. This is Requirement 1,
fully satisfied.*

### Hello World, deployed by GitOps instead of by hand (Requirements 2, 3, 4)

With both clusters reachable, the next question was how the actual
application should get onto them. The straightforward way is `kubectl
apply` - write the YAML, run one command, done. Instead, this project
deploys Hello World through ArgoCD, following a practice called GitOps: a
Git repository is treated as the single source of truth for what should be
running, and a tool - here, ArgoCD - continuously watches that repository
and reconciles the cluster to match it automatically. Nobody runs a deploy
command; pushing to Git *is* the deploy.

One ArgoCD installation runs on West Europe and manages both clusters from
there, rather than installing a separate, disconnected ArgoCD per region -
partly because it's a more convincing thing to demonstrate (one push,
both regions update), and partly because it's simply less to maintain. The
actual Kubernetes manifests are organized with Kustomize: one shared base
(the Deployment, Service, HPA, Ingress, and cert-manager's `ClusterIssuer`)
that both regions build on, plus a small overlay per region containing only
what's genuinely different between them - each one's own identity text and
its own certificate request.

Installing ArgoCD itself hit one immediate, narrow limit: one of its own
Custom Resource Definitions (a CRD - a way to teach Kubernetes about a new
object type it didn't originally know, the same mechanism cert-manager uses
for `Certificate`) is large enough that `kubectl apply`'s normal method -
storing a full copy of what was applied inside an annotation on the object,
so it can diff against it next time - exceeded Kubernetes' hard 256KB limit
on any single annotation. The fix was `--server-side`, which tracks the
same diff on the API server itself instead of in that annotation, sidestepping
the limit entirely.

![Every ArgoCD pod running after the server-side install](docs/screenshots/34-argocd-pods-running.png)
*Seven pods, all `Running` - the control plane that everything else in this
section deploys through.*

Connecting ArgoCD to Germany West Central - a second, separate cluster it
needs to manage remotely - surfaced the same category of firewall gap as
the K3s join incident earlier, just between two clusters instead of two
nodes in one cluster: traffic from a pod on West Europe reaching Germany
West Central's public address doesn't count as "internal" to Azure, even
though both belong to the same project. The firewall needed an explicit
rule allowing each region's own known addresses to reach the other's
Kubernetes API port - written generally, by port and by known address, so
any future tool needing this kind of access is already covered, not just
ArgoCD. ArgoCD reported this as `InvalidSpecError` - it simply didn't
recognize Germany West Central as a cluster it was allowed to deploy to,
until the firewall rule and the cluster registration were both actually in
place.

A second gap appeared right after: the sync itself failed because
cert-manager - the tool that actually issues the self-signed certificate
Requirement 4 needs - had never been installed on either cluster. The
`ClusterIssuer` and `Certificate` manifests were written assuming it would
already be there; it wasn't, because installing it had never actually made
it into the list of steps.

![cert-manager missing - ArgoCD explaining exactly what it couldn't find](docs/screenshots/35-cert-manager-missing-error.png)
*"Make sure the 'Certificate' CRD is installed on the destination
cluster" - ArgoCD's own error naming the actual missing piece.*

Installed on both clusters the same way as ArgoCD itself - trusting
cert-manager's own official installer rather than hand-writing it.

![cert-manager running on both clusters](docs/screenshots/36-cert-manager-installed-both-clusters.png)
*Three pods per cluster, six total - the piece that was missing.*

With both gaps closed, the sync actually succeeded, and ArgoCD's own
health checks - not just "did the command exit with 0," but "is the
resulting Deployment actually passing its readiness checks" - confirmed
it.

![West Europe, fully synced and healthy](docs/screenshots/37-west-eu-synced-healthy.png)
*Every resource ArgoCD manages for this region - `Synced` and `Healthy`.*

![Germany West Central, fully synced and healthy](docs/screenshots/38-germany-west-synced-healthy.png)
*The same result, independently, for the second region.*

### The certificate that looked right until it was actually checked

Everything above reported success - `Healthy` in ArgoCD, a certificate
object that existed and was marked ready. But checking the actual browser,
rather than trusting the green status, told a different story: the
certificate presented was Traefik's own generic built-in one, not the real
certificate cert-manager had issued.

![The wrong certificate - Traefik's generic default, not the real one](docs/screenshots/42-traefik-default-cert-bug.png)
*`TRAEFIK DEFAULT CERT` - technically a certificate, just not the one this
project actually built.*

The reason: Traefik decides which certificate to present using SNI
("Server Name Indication" - the hostname a browser sends during the TLS
handshake, before it even asks for a specific page), matched against the
hostnames configured on each Ingress. This project deliberately has no
hostname at all - raw IPs only, per the "don't spend money on domains"
rule - so Traefik had nothing to match against, and silently fell back to
its own default rather than erroring. The real certificate was never
broken; Traefik simply never knew to offer it.

The fix is a `TLSStore` - one of Traefik's own custom resource types - that
names a specific certificate as the *default*, used for any connection that
doesn't match a more specific rule. One per region, since each runs its own
separate Traefik instance with its own certificate.

![The real certificate, confirmed on both regions](docs/screenshots/43-real-cert-west-eu-fixed.png)
*Issued at the exact second cert-manager created it, expiring roughly 90
days later - cert-manager's own default duration. Genuinely the right
certificate this time, not just a status field saying so.*

![The same fix, confirmed on Germany West Central too](docs/screenshots/44-real-cert-germany-west-fixed.png)
*Same result, independently, for the second region.*

### The result

![Hello World, live over HTTPS - West Europe](docs/screenshots/39-hello-world-west-eu-https.png)
*Requirements 2 and 4, actually working: a real certificate, terminated by
Traefik, in front of the application.*

![Hello World, live over HTTPS - Germany West Central](docs/screenshots/40-hello-world-germany-west-https.png)
*The same application, the same certificate mechanism, an entirely
separate cluster and region.*

![ArgoCD's own dashboard, reachable and ready to sign in](docs/screenshots/41-argocd-ui-login.png)
*The GitOps control plane itself - the thing that turned a `git push` into
both regions updating automatically.*

**A deliberate choice worth being explicit about:** ArgoCD is reached here
through `kubectl port-forward` - a temporary tunnel from this laptop into
the cluster - rather than through a permanent public link. A real Ingress
for ArgoCD is entirely possible (it officially supports being served under
a URL subpath, so it could share the same address as Hello World without
needing a second one), but for a project this temporary and disposable, the
extra public attack surface isn't worth it just for convenience - the
tunnel already does the job, and it costs one command to bring back
whenever it's actually needed.

This is also honestly closer to how real production teams run it than a
public link would be: enterprises rarely expose ArgoCD to the open
internet either. The far more common pattern is keeping it reachable only
from inside a private network or VPN, behind real company logins (SSO -
"Single Sign-On," so nobody's juggling a separate ArgoCD-specific password)
rather than the one shared `admin` account this project uses, with
fine-grained permissions controlling which teams can even see or sync
which applications - not everyone gets the same full access this project's
sandbox admin account has.

The same question applies to how ArgoCD notices a change in Git in the
first place - covered earlier in this section (periodic polling, every few
minutes, with a webhook as an optional speed-up, not a replacement). Real
production setups almost always run both together: polling as the
always-on safety net that keeps working even if a webhook delivery ever
fails or was never configured, with a webhook layered on top so the common
case reacts in seconds instead of minutes. That webhook, though, needs
Git's hosting service to be able to reach ArgoCD directly - which needs
exactly the kind of permanent public address this project deliberately
chose not to build. The two decisions are connected, not separate ones.

## Screenshots

This section fills in as each part of the platform actually comes to life -
each entry below will link to an image once that step has been completed
and verified.

- [x] Isolated resource groups and a scoped sandbox identity (above)
- [x] Terraform's state storage created, and Terraform initialized (above)
- [x] Terraform successfully planning the infrastructure (above)
- [x] Infrastructure actually applied - both virtual machine scale sets live (above)
- [x] Both clusters showing healthy, ready Kubernetes nodes, reached
      directly from my own laptop (above) - **Requirement 1 done**
- [x] The Hello World page, loaded securely in a browser (above) -
      **Requirements 2 and 4 done**
- [ ] The application automatically adding more servers under load
- [ ] Traffic automatically switching to the second region during a simulated failure
- [x] The GitOps dashboard showing both clusters in sync (above)
- [ ] The Google Cloud server, built with the same automation
- [ ] A real DNS troubleshooting session on a server

## How this is being built

The day-to-day plan, including exactly what's done and what's next, lives in
[PLAN.md](PLAN.md). The deeper architecture reasoning is in
[ARCHITECTURE.md](ARCHITECTURE.md) (currently being rewritten to match the
simplified plan). Every piece of infrastructure code has its own explanatory
comments written directly alongside it, so the reasoning for a decision
lives right next to the decision itself. [cli-output-recap-reminder.md](cli-output-recap-reminder.md)
explains the recurring tool output shown throughout this document - the
Ansible, Terraform, and kubectl fields that appear in screenshot after
screenshot - field by field.

## Author

Denis Riungu — [LinkedIn](https://linkedin.com/in/denis-riungu)
