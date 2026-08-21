# Backup & recovery concept — Requirement 7

> CGI's brief asks: *"Describe in broad strokes how you handle a scenario
> with two options. Zero-down time and a maximum MTTR (Mean Time To
> Recovery - the average time between something breaking and it being
> fixed) of 4 hours."* The two options are zero downtime and a ≤4-hour
> MTTR. This is a description requirement, like Requirement 6 - a clear,
> well-reasoned answer earns full credit without a disaster-recovery drill
> actually being run live.
>
> [Verify against the full brief →](CGI-Challenge-Brief.md#requirement-7)

## What actually needs backing up here

The Hello World application is **stateless** - it holds no data of its
own. Every resource it needs (Deployments, Services, ConfigMaps, the
Ingress, the cert-manager `Certificate`) is a YAML file, version-controlled
in Git, deployed through ArgoCD. Git is the source of truth. The cluster
is just a live copy of whatever Git currently says should exist, and it
can be rebuilt from Git at any time.

That means this app has no data-loss risk to plan for, only an
infrastructure-loss risk. A real production system built on this platform
would eventually have genuine state somewhere - a database, user uploads,
something a redeploy can't recreate on its own. Velero, covered near the
end, is the answer for that case, described because CGI's brief expects
it, not because this demo currently needs it.

## Two disasters, two recovery paths

**Scenario A - something breaks at the application level.** A bad deploy,
a crash-looping pod, someone running `kubectl edit` by hand and drifting
the cluster away from what Git says it should be. This is already solved,
live, right now: every ArgoCD Application in this platform has
`syncPolicy.automated.selfHeal: true` set (`k8s/argocd/application-*.yaml`).
ArgoCD continuously compares the cluster's real state against Git, and the
moment they disagree, it re-applies Git's version automatically - no human
has to notice or step in. This is the fastest, most common recovery path
this platform has, and it's already running today, not just described.

**Scenario B - a whole cluster or region is lost.** The VMSS gets deleted,
a region has a real outage, someone removes the wrong resource group. The
recovery path reuses the same three tools that built the platform in the
first place, since everything about it is already version-controlled and
re-runnable:

1. **`terraform apply`** rebuilds the lost region's infrastructure -
   resource group, VNet, NSG, Load Balancer, VMSS.
2. **The Ansible playbook** re-provisions K3s on the new nodes, using the
   same `common` → `k3s-server` → `k3s-agent` roles from the original
   build.
3. **ArgoCD reconnects and resyncs.** If West Europe (where ArgoCD lives)
   is the region that survived, it just notices the new cluster and
   deploys Hello World to it, with no manual `kubectl apply` step. If West
   Europe is the region that was lost, ArgoCD needs reinstalling first - a
   scripted, already-documented step, not something improvised on the day.

None of these three steps are new procedures - each one is a command
already used to build the platform, captured in `how-the-build-works.md`.

## Why "zero downtime" doesn't need its own mechanism

Zero downtime for users isn't something built separately for this
requirement - it falls out of a decision already made for Requirement 5.
Two independent regions already serve the same app behind the self-hosted
proxy, so losing one region doesn't interrupt real traffic in the first
place: the proxy's health check detects the failure and routes around it
automatically, exactly as shown in the Requirement 5 failover demo. The
failed region's recovery then happens without time pressure, because users
were never actually affected while it was happening. Multi-region HA
(High Availability) and disaster recovery aren't two separate features
here - the first is most of what makes the second one's "zero downtime"
target real instead of aspirational.

## Why the MTTR target has real margin - a real, measured incident, not a guess

This platform has never been rebuilt from scratch end to end, so Scenario
B's exact timing is an estimate, not a measurement. But a real incident
during this build gives a genuine, timestamped number for a harder
case than Scenario B: the pod-scheduling deadlock documented in
Requirement 3's write-up (a rolling update that got permanently stuck).
ArgoCD showed the problem `Degraded` at **20:09:56**. The fix was
diagnosed from scratch (a problem never seen before, with no known
solution to just re-run), written, committed, and deployed, and ArgoCD
confirmed `Healthy` again at **20:53:57** - both timestamps taken directly
from the screenshots documenting the incident. That's **44 minutes**,
start to finish, for a problem that required genuine live troubleshooting.

Scenario B's routine region rebuild - `terraform apply`, the Ansible
playbook, ArgoCD resync - has no equivalent diagnosis step, since it's
re-running commands that already worked once. It's reasonable to expect
it to land at or under that same 44-minute mark, though that specific
scenario hasn't actually been timed. Either way, both numbers sit
comfortably inside the 4-hour target, and users saw zero downtime
throughout, since the surviving region kept serving the whole time.

## Velero's actual job, and why it isn't on this critical path

**Velero** is the standard Kubernetes-native backup tool. It snapshots
cluster object state and, optionally, persistent volume data, storing the
result outside the cluster - Azure Blob Storage, which has a genuine free
tier, would be the natural choice here. A production deployment of this
platform would run it on a schedule, protecting whatever stateful
component a real version of this app eventually has - a database's actual
rows, not anything a redeploy from Git could already rebuild.

Two things worth being direct about: Velero's snapshots never take the
running application offline - a backup running is not a downtime event.
And for this specific app, Velero isn't part of the recovery story above
at all, because there's no stateful data yet for it to protect. Scenario A
and Scenario B are both fully solved by Git and the tools that built the
platform. Velero would close a gap - real persistent data - that doesn't
exist here yet, but would in a production system built on this same
foundation.

## What's live versus described, and why that split is reasonable

`selfHeal: true` is real and already running - Scenario A is provable
live, in seconds, on request. Scenario B's recovery path is described
rather than performed, because deleting and rebuilding a live region to
prove a point would risk the infrastructure the rest of the presentation
depends on, for a requirement that only asks for broad strokes. Velero is
explained rather than installed for the same reason: it protects data this
demo doesn't have, so installing it would demonstrate the tool without
demonstrating anything this platform actually needs.
