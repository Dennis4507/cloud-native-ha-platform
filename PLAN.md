# PLAN.md — what we're actually doing, right now

This is the current source of truth. `ARCHITECTURE.md` and `CLAUDE.md` still
describe an earlier, bigger version of this project and haven't been trimmed
to match yet — don't treat them as current until they're edited. This file is
short on purpose. If it starts growing past a page, that's a sign to stop and
simplify again rather than let it become the next CLAUDE.md.

## The challenge, in one paragraph

CGI Cloud & DevOps Challenge. 8 requirements, up to 4 days, present live over
MS Teams to 4 CGI staff (Kevin Sandermann, Luca Rodehutskors, Christoph
Schlosser, Raphael Krüger). Hard rule from the brief: don't spend any money
on infrastructure, domains, or certificates. Azure is explicitly sanctioned;
a CGI-provided Azure sandbox is available on request (status: not yet
requested/confirmed).

## The 8 requirements, one line each

1. K8s cluster via IaC — `kubectl get nodes` shows 2+ `Ready` nodes
2. Hello World container, reachable in a browser
3. Multiple instances, round-robin traffic, autoscale on CPU (HPA)
4. Ingress controller terminating TLS with a valid cert (self-signed is fine)
5. Multi-region HA — second cluster, deployed the same way, traffic routed
   by a proxy or a PaaS service (both explicitly allowed)
6. Monitoring — **describe** the concept (not required to fully deploy)
7. Backup/recovery — **describe** the concept, zero downtime + MTTR ≤ 4h
8. DNS debugging methodology on a node (their scenario says "AKS node")

## Decided scope

**Core (builds Req 1–5, all on Azure):** 2× K3s clusters on Azure VMSS (West
Europe + North Europe) via Terraform + Ansible. Hello World with pod
anti-affinity, HPA, Traefik ingress + self-signed TLS. Multi-region failover
via a free self-hosted NGINX/HAProxy proxy (Traffic Manager is a possible
later swap, only if the CGI sandbox gets confirmed — real money otherwise).

**Two cherries, deliberately just two:**
- **GCP showcase** — one Always-Free Compute Engine VM (must be in
  `us-central1`/`us-west1`/`us-east1` — the free tier does *not* cover
  `europe-west3`), same Ansible playbook, single-node K3s. Isolated from the
  graded HA path — it can never break Requirement 5's demo.
- **GitOps via ArgoCD** — Git as source of truth, ArgoCD auto-syncs both
  Azure clusters. Real live-demo risk here: sync isn't instant, so rehearse
  the timing before relying on it live.

**Explicitly cut, not built:** Hetzner, Stackit, AWS, Liqo, sovereignty-mode
routing, a full Prometheus/Grafana/Loki stack, Sealed Secrets, Trivy. None of
these answer any of the 8 requirements. If asked about them live, they're
"here's what I'd add next" answers, not demo material.

**Parked as a maybe, only if there's real spare time at the end:** a
WireGuard/OpenVPN VPN into one of the existing VMs, so ArgoCD (and anything
else currently reached via `kubectl port-forward`) could be accessed
through a private tunnel instead - closer to how real enterprises reach
ArgoCD than either a port-forward or a public link. Doesn't answer any of
the 8 requirements either, and Requirement 3 (finishing the live k6/HPA
demo) and Requirement 5 (the proxy failover, not yet started) both come
first. The written explanation already in README already covers this
question for the presentation - building it is a nice-to-have on top of
that, not something the answer depends on.

**Requirements 6 and 7 are description requirements** — a clear written
concept document is enough. A lightweight live Uptime Kuma dashboard is a
cheap bonus (mainly because it makes the Requirement 5 failover demo more
convincing), not a requirement in itself.

**Requirement 8** is a rehearsed methodology (kubectl exec → nslookup →
CoreDNS → node → iptables → tcpdump), not necessarily something broken live
in front of the panel.

## What's actually on disk right now

Just the scaffold folders, plus:
`ARCHITECTURE.md`, `CLAUDE.md`, `README.md`, `cgi-presentation-script.md`,
`docs/failover-runbook.md` — all five still reflect the earlier, bigger plan
and need trimming as we go. Everything else built earlier today (Terraform,
the bootstrap script, `Makefile`, `platform.yaml`, the hetzner/stackit/aws
terraform folders) has been deleted.

## Azure account setup — done

CGI's brief offers a sandbox on request, but there wasn't time to wait on it
inside the 4-day window, so this project provisions its own equivalent
sandbox instead. The root account was used only to set this up once. All
project work from here on runs as `cgi-sandbox`, a separate Entra identity
with `Contributor` on `rg-ha-platform` and `Contributor` +
`Storage Blob Data Contributor` on `rg-tfstate` — scoped to just those two
resource groups, nothing subscription-wide, and no permission to grant
access to itself or anyone else. Screenshotted in `README.md`. Settled as
sufficient — no further tightening planned.

## Next actions, in order

- [x] Terraform: resource group, 2× VNets/subnets, 2× Load Balancers +
      Public IPs, 2× VMSS (`Standard_D2s_v3`, West Europe + Germany West
      Central), one Managed Identity, NSGs locked to Denis's own IP - live
      in the real subscription
- [x] Ansible: `common` role (swap off, sysctl, br_netfilter), `k3s-server`
      role, `k3s-agent` role
- [x] Verify: `kubectl get nodes` shows 2 `Ready` nodes on each cluster,
      run directly from Denis's own laptop (not over SSH) →
      **Requirement 1 done**
- [x] Hello World: Deployment + Service + ConfigMap (per-region identity
      text), required pod anti-affinity, HPA, Traefik ingress + cert-manager
      self-signed TLS → **Requirements 2 and 4 done, live and verified on
      both regions** - deployed via ArgoCD, real certificate confirmed in
      browser (not Traefik's default - see README for that incident and
      the `TLSStore` fix). Requirement 3's autoscaling half (the k6/HPA
      live demo) still to actually run - see below.
- [x] `scripts/load-test.js` (k6): drives real CPU load against Hello World
      so the HPA scale-up (2→6→8 pods) is genuine, not staged - watched live
      in `k9s` during the presentation. Exact VU count to reliably trigger
      scaling needs real tuning during rehearsal, not guessable in advance.
- [x] Live k6/HPA demo → **verified**: HPA scaled 2 → 5 replicas under real
      k6-generated load (300 VUs, ~1,457 req/s peak), watched live in `k9s`.
      Round-robin proof needed a fix first: both pods in a region served
      identical HTML, so nothing visibly proved which pod answered a given
      request. Added `nginx-config.yaml` (one `add_header X-Pod-Name
      $hostname always;` line) to fix that - which then surfaced a real
      scheduling deadlock (documented in README): `deployment.yaml`'s
      `required` anti-affinity and `hpa.yaml`'s `maxReplicas: 10` disagreed
      about how much room 2 nodes actually have, so a 3rd pod deadlocked in
      `Pending` permanently. Fixed via `maxSurge: 0` (free a node before
      scheduling the replacement) and switching anti-affinity to
      `preferred` (stack rather than deadlock past node count) - both
      ArgoCD Applications back to `Healthy`/`Synced`. Round-robin proof run
      for real, combined with a second live k6 run: curl loop, k6, and
      `k9s` running simultaneously in 3 panes, watched scaling from 2 → 6
      pods while the curl loop's rotation grew from 2 → 6 pod names in
      lockstep - both halves of Requirement 3 proven together, live, in
      one continuous run → **Requirement 3 done**.
- [x] Self-hosted proxy: NGINX installed via its own Ansible role on the GCP
      showcase VM, 2 upstreams (West Europe primary, Germany West Central
      backup) + passive health checks (`max_fails`/`fail_timeout`), self-
      signed TLS of its own, `scripts/failover-demo.sh` written - **build
      verified**: `curl -sk https://<proxy-ip>/` returns West Europe's page
      through the proxy over HTTPS. Real incident along the way (documented
      in README): the same slow Always Free disk from the GCP incident above
      wedged the plain `apt-get install nginx` step too, first via Ubuntu's
      own background `apt-check` process stuck in an unkillable D-state, and
      second - the actual root cause of most of the delay - via retrying the
      playbook without checking a previous run had exited, leaving two
      `ansible-playbook` processes fighting over the same lock.
      `failover-demo.sh break`/`restore` both run for real, watched live
      across browser, Uptime Kuma, and CLI simultaneously - real incident
      caught mid-demo too: the script's NSG rule priority (90) was below
      Azure's allowed 100-4096 range, fixed to 105 → **Requirement 5 done**
- [x] ArgoCD: installed on West Europe, manages both clusters from there,
      Application per region pointing at its Kustomize overlay (cherry #1) -
      **live and verified**: both Applications show `Synced`/`Healthy`,
      Hello World actually running on both clusters, deployed entirely by
      `git push` rather than `kubectl apply`.
- [x] GCP: **live and verified** - `kubectl --context gcp-showcase get
      nodes` shows one `Ready` node, reached directly from the laptop,
      same as both Azure clusters (cherry #2 done). Real incident along
      the way: the Always Free tier's disk (standard/HDD, the only option
      it covers) caused severe I/O wait (91.8%) that made K3s's own
      internal database time out against itself - fixed by disabling
      Traefik and ServiceLB on this node specifically, since this showcase
      never runs anything that needs either. This same VM now also runs the
      standalone NGINX proxy for Requirement 5, as its own process alongside
      K3s - see the proxy line above.
- [x] Cost claim checked with real evidence, not just asserted: GCP
      billing confirmed at a real €0.00 for the whole build; Azure's real
      cost (~€12) documented honestly with a reason - `Standard_B2s` (the
      cheaper SKU) had no available capacity on this subscription in
      either region, confirmed in `terraform/azure/variables.tf`;
      `Standard_D2s_v3` costs 2.5x more per hour ($0.12 vs $0.048,
      verified against Azure's live retail pricing API) - the actual cost
      of a real capacity constraint, not a design choice.
- [x] Uptime Kuma: **live and verified** - deployed via ArgoCD, both
      regions' real HTTPS endpoints monitored (West Europe, Germany West
      Central), TLS errors correctly ignored (self-signed certs), interval
      and timeout tuned down for a snappier live demo. A third monitor now
      also watches the proxy's own address (`(GCP) Failover Proxy`),
      independent of the two direct region monitors. Written
      `requirement-6-monitoring-concept.md` doc done - see below.
- [x] `requirement-6-monitoring-concept.md` (Req 6) → **done**: two-layer framing
      (Uptime Kuma = external synthetic checks, ArgoCD Healthy/Degraded =
      internal resource health), backed by two real incidents from this
      build as evidence rather than hypotheticals - the pod-scheduling
      deadlock (ArgoCD caught it, Uptime Kuma couldn't see it) and the
      Requirement 5 failover demo (the reverse: Kuma caught it, ArgoCD
      couldn't). Azure Monitor and Prometheus/blackbox-exporter/Grafana
      covered as the production-scale alternatives, not built live.
- [x] `requirement-7-backup-recovery-concept.md` (Req 7) → **done**: two scenarios
      (app-level drift, solved live by `selfHeal: true` - confirmed set on
      all 3 ArgoCD Applications; whole-region loss, solved by re-running
      Terraform + Ansible + ArgoCD resync). "Zero downtime" framed as a
      side effect of Requirement 5's multi-region HA rather than a separate
      mechanism. MTTR backed by a real measured number, not a guess: the
      Requirement 3 pod-scheduling deadlock, diagnosed from scratch and
      fully resolved, took 44 minutes start to finish (20:09:56 Degraded →
      20:53:57 Healthy, both from screenshot timestamps) - a harder case
      than a routine region rebuild since it needed live diagnosis, still
      comfortably inside the 4-hour target. Velero explained as the
      production answer for genuinely stateful data, explicitly not on
      this app's critical path since Hello World has none.
- [ ] Live Req 7 demo, using ArgoCD's selfHeal (already configured) rather
      than building anything new: scale the Hello World deployment down by
      hand with `kubectl`, bypassing Git, and show ArgoCD noticing the
      drift and restoring it automatically - a real, fast, safe proof of
      "the platform recovers on its own," at zero extra build cost
- [x] `requirement-8-dns-debug-runbook.md` (Req 8) → **done**: a straight
      methodology answer, same treatment as Requirements 6 and 7 - a
      description, not a staged live demo. TCP/IP-model-framed: start at
      `kubectl get pods`, narrow down through CoreDNS health and node
      config, explain why packet capture (`tcpdump`) is the right method
      once configuration checks stop giving new information, correlate
      with `iptables`, note recovery is automatic (`kubelet` retries on
      its own). No fabricated test pod or scenario - a live/recorded take
      was attempted first but abandoned after repeated timing issues
      (kubelet's retry backoff vs. tcpdump's capture window kept costing
      full re-recordings); a clear written methodology was the more
      reliable answer, and one CGI's own wording explicitly allows.
      Includes the AKS bridge: self-managed K3s uses SSH, real AKS would
      use `kubectl debug node` instead - same methodology either way.
- [ ] GitHub Actions CI (`tflint` → `checkov` → `helm lint`) - deliberately
      last, since it checks code that needs to already be finished and
      stable for the checks to mean anything
- [x] `docs/architecture_diagram.py` → **done**: full architecture, real
      Azure/GCP/GitOps components (verified against the actual `diagrams`
      library classes installed, not guessed) - GitHub as source of truth,
      Terraform/Ansible provisioning all 3 node groups, ArgoCD managing
      both Azure clusters, the GCP node running K3s + the failover proxy,
      Uptime Kuma's independent health checks, GitHub Actions shown as
      planned/not yet built. Embedded in README as `docs/architecture.png`.
- [x] `cgi-presentation-script.md` → **done, second full rewrite**:
      restructured again per Denis's direction - 14 milestones in real
      build order (server choice → sandbox → Terraform → Ansible → ...),
      not requirement-number order, since that's how it actually happened
      and reads more naturally live. Each milestone tagged with its
      requirement(s). Scaffold explained file-by-file for Terraform/
      Ansible/GCP, with VMSS and LB acronyms expanded and the reasoning
      for choosing VMSS stated explicitly. Every incident follows the
      same shape: the issue → what was actually found → the fix - not
      just "it broke, here's the fix." Bold headers throughout so it
      works as both a live script and a skimmable reference. README stays
      the thorough browsing reference; this is what gets presented from.
- [ ] Timed rehearsal - rehearsal
      needs to specifically include a live run-through of the actual build
      sequence (Terraform creating the servers, Ansible configuring them),
      not just the finished result - and specifically the moment certain
      commands cause new files to appear on disk (kubeconfig files fetched
      by the k3s-server role, merged-kubeconfig.yaml from the merge
      script) so Denis can explain *why* each file exists and what created
      it if a panel member asks, rather than being caught off guard by his
      own file tree mid-demo.
- [x] `cli-output-recap-reminder.md` - a field-by-field reference for the
      recurring terminal output (Ansible's PLAY RECAP, Terraform's plan
      symbols, kubectl's columns) shown across every screenshot. Read this
      before the presentation - anything visible on screen is fair game
      for a question.

**Don't forget before the presentation:** `automatic_instance_repair` is
currently disabled in `main.tf` (discovered live during Ansible setup - it
was replacing instances mid-session because nothing was listening on port
80 yet, which broke the Ansible inventory each time). Re-enable it
(`enabled = true`) once the Hello World app is actually deployed and
port 80 has something real to check.

## Screenshots — capture as we go

Folder: `docs/screenshots/`. Naming: `NN-short-description.png`, numbered in
build order (e.g. `01-kubectl-get-nodes.png`, `02-hello-world-browser.png`)
so they sort in the order they'll be needed. Every screenshot does double
duty: it fills in one of the checkboxes in `README.md`'s screenshot section
(so anyone reading the repo can follow along and see the platform actually
working, not just take the claims on faith), and it becomes a real slide or
talking point in `cgi-presentation-script.md` rather than something
described from memory. I'll call out explicitly, every time a step reaches
a screenshot-worthy moment, what to capture and which of the two documents
it belongs in — Denis takes it (Win+Shift+S is the fastest capture tool),
and I wire the filename into both places right after.

**Standing reminder, not yet captured:** `terraform plan` running clean
against the real Azure subscription — that's the first one still owed, from
when the Terraform files were finished.

Planned shots, one per graded requirement plus each cherry (add more if a
step produces something worth showing, but this is the minimum so nothing
gets forgotten):

- [ ] `terraform plan` output, clean run against the real subscription (proves the IaC actually works)
- [ ] `kubectl get nodes` — both clusters, 2 Ready each (Req 1)
- [ ] Browser — Hello World over HTTPS, cert details visible (Req 2, 4)
- [ ] `k9s` mid-HPA-scale-up (2→6+ pods) during the `k6` load test (Req 3)
- [ ] Repeated `curl` output showing round-robin alternation across pods (Req 3)
- [ ] Before/after of the Requirement 5 failover — browser showing West EU,
      then North EU, plus the proxy/health-check output during the switch
- [ ] ArgoCD UI — both clusters `Synced`/`Healthy` (GitOps cherry)
- [ ] `kubectl get nodes --context gcp-showcase` — 1 Ready node (GCP cherry)
- [ ] DNS debug runbook — real captured `tcpdump`/`nslookup` output (Req 8)

## Never — no exceptions

**Denis runs every command related to this project's actual infrastructure
or cluster — setup, verification, and demo alike.** Claude also never
prompts Denis to decide whether to run something that creates real
infrastructure or spends money (e.g. "apply now or wait?") — that decision
gets initiated by Denis, not offered as a choice. Claude reports status
(plan is clean, X resources ready) and stops there. Not just the risky ones
(`terraform apply`/`destroy`, `az` commands that create/start/stop/delete a
resource, `kubectl apply`/`delete`, `git push`) but also the read-only ones
that will be typed live in front of the panel (`terraform plan`, `kubectl
get nodes`, `curl`, the failover script, the DNS debug commands). The reason
is bigger than safety: these are the exact commands Denis needs to be able
to run fluently and explain on the spot during the presentation, and that
only comes from typing them himself, not from watching Claude run them.
Claude writes the code, explains what a command will do and why before it's
run, and reviews the output Denis reports back — but doesn't execute
anything against the real Azure subscription, the cluster, or GitHub.

## Presenting commands — plain over flag-heavy

When a command can be run either plainly (letting it prompt interactively)
or with flags that pre-fill the answers, default to the plain version. This
is a job-interview presentation, not a script - typing `terraform plan` and
answering its prompts live reads as genuine; a long command stuffed with
`-var` flags reads as rehearsed. Only reach for the flagged version when the
plain one genuinely can't work live (e.g. something that needs a value too
long or fiddly to type cleanly on the spot).

## Rules staying in effect

- 3 build steps per session, then stop for Denis to confirm before continuing.
- Every step explained out loud in full plain-English sentences, acronyms
  expanded on first use — Denis needs to be able to repeat it to the panel.
- **Guidance happens in chat, not in files.** Walking through what a step does
  and why happens here in the conversation — that's the primary way Denis
  learns each piece, not something he has to reconstruct by reading a file
  afterward.
- **No separate per-phase write-ups.** That split (notes living apart from
  the code they describe) is what caused the notes to go stale and thin.
  `README.md` is the one human-facing status document — what this project
  is, what's done, what's next, and the screenshots — and it gets updated as
  each piece is finished, not written up separately afterward.
- **Code comments carry the real explanation, and they have to actually read
  like something a person wrote for another person.** Not clipped fragments,
  not jargon stacked on jargon — full sentences that say what a section is
  building and why, the way you'd explain it out loud to someone who didn't
  write it. Every resource block gets a short intro comment before it, not
  just a side-note after.
- No domain purchase, no paid certs, no Traffic Manager unless the CGI
  sandbox is confirmed, GCP VM must be in a genuinely Always-Free region.
