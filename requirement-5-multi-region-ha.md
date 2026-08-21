# Requirement 5 — Multi-region high availability

> CGI's brief: *"Design a high available scenario for a K8s cluster based
> on a multi-region approach. Traffic routing should be simulated with a
> proxy-server as loadbalancer or with a PaaS cloud-native service. Deploy
> the scenario the same way as part 1 of the challenge."*
>
> [Verify against the full brief →](CGI-Challenge-Brief.md#requirement-5)

**In short:** a second, independent cluster in Germany West Central,
built the same way as the first, with a self-hosted NGINX proxy routing
traffic between them. Live failover demonstrated across a browser,
Uptime Kuma, and the command line at the same time.

## What I built

- **A second K3s cluster, Germany West Central** — deployed with the
  exact same Terraform and Ansible as Requirement 1's cluster, nothing
  hand-built differently.
- **A self-hosted NGINX reverse proxy**, running on the GCP showcase VM
  — the one piece of infrastructure genuinely outside both Azure
  regions, so it can't fail alongside whichever region it's watching.
  Routes to West Europe (primary) and Germany West Central (backup),
  switching automatically based on real health checks.
- **A third Uptime Kuma monitor**, watching the proxy's own address
  independently of the two regions it routes between.

## Why a self-hosted proxy, not a managed PaaS traffic service

The brief names both as equally valid. I checked every realistic managed
alternative directly against its own current pricing before choosing —
not assumed the free route by default:

| Option | Free health-check failover? | Needs a domain? |
|---|---|---|
| Azure Traffic Manager | No — bills for health checks themselves, continuously | Yes |
| Azure Front Door | No — $35/month minimum | Yes |
| AWS Route 53 | Only for AWS-hosted endpoints; $0.75/check/month for external | Yes |
| Cloudflare Load Balancing | Paid add-on, not on the free plan | Yes |
| Cloudflare Workers | Free, but can't target a bare IP address at all | Effectively yes |

**Every single option needs a real registered domain somewhere in the
chain** — which the brief's own "no domain" rule rules out entirely, on
its own. A self-hosted NGINX proxy does the same job — check a backend's
health, forward to whichever is up — for zero cost, and it's literally
the other option the brief names, not a fallback.

**A limitation worth stating plainly:** NGINX's health check on the
backup region is *passive* — it only learns a server is down by watching
real requests fail, and the backup receives zero real requests while the
primary is healthy. If both regions failed at the same instant, the
proxy wouldn't discover the backup was also down until it tried to use
it. The production fix (a Cluster Autoscaler-style active prober, or a
managed DNS-based service with its own active health checks) is
described in the concept docs rather than built, deliberately — one more
live moving part isn't worth the risk for a limitation this narrow.

## Live demo

```bash
bash scripts/failover-demo.sh break     # simulates West Europe failing
bash scripts/failover-demo.sh restore   # undoes it
```

![Baseline: all three monitors green before anything is touched](docs/screenshots/70-kuma-baseline-three-monitors-green.png)

![Uptime Kuma independently catching West Europe going down](docs/screenshots/73-kuma-west-europe-down-alert.png)

![The browser, refreshed, now showing the backup region](docs/screenshots/75-browser-failed-over-germany-west-central.png)
*Same address, `https://136.115.185.153/`, different region — the user
experienced nothing; the platform rerouted itself.*

![The CLI loop transitioning back once West Europe answers again](docs/screenshots/76-cli-loop-live-transition-back-to-west-europe.png)
*Nothing manually pointed back at West Europe — NGINX's own health check
retried it on schedule and switched back automatically.*

**Requirement 5, done** — a simulated regional failure, detected and
routed around automatically, watched from three independent angles at
once, with recovery just as automatic as the failover itself.

---

## Incidents along the way

**⚠️ Installing the proxy took close to six hours — the longest single
debugging session of the build.**
Two separate problems stacked on top of each other:

1. **Ubuntu's own background update-checker got stuck in an unkillable
   kernel state** (`D`-state — uninterruptible sleep) on the GCP VM's
   slow disk, blocking the package-manager lock every install needs.
2. **The real cause, found later: duplicate `ansible-playbook`
   processes.** Retrying the install multiple times without confirming
   the previous attempt had actually finished left several
   `ansible-playbook` runs fighting over the same lock simultaneously.

**The fix:** masked the update-checker's triggers, and — the real
lesson — check `ps aux | grep ansible-playbook` before every retry, never
assume a previous run has finished.

**⚠️ The failover script itself failed on the first real run.**
Its NSG (Network Security Group — Azure's firewall) rule used priority
90; Azure only accepts priorities from 100–4096. Fixed by moving it to
105 — still evaluated ahead of the existing allow-rule at 120, just
inside the range Azure actually accepts.

![The priority-90 rejection, then the fix confirmed working](docs/screenshots/72-break-command-priority-fix-confirmed.png)
*Left in on purpose rather than cropped out — a wrong value caught and
fixed against a real API response is more honest than a script that only
ever ran once.*
