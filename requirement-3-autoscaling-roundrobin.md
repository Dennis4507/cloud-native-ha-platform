# Requirement 3: Autoscaling & round-robin traffic

> CGI's brief: *"The container should be deployed on multiple nodes, with
> traffic being distributed to the instances according to the round-robin
> principle. The container instances scale automatically based on the CPU
> load."*
>
> [Verify against the full brief →](CGI-Challenge-Brief.md#requirement-3)

**In short:** two things proven together, live, in one continuous run.
The app scales automatically from 2 to 6 pods under real load (`k6` +
`HPA`), and traffic genuinely round-robins across every one of them,
watched via a per-pod response header.

## What I built

- **HPA (HorizontalPodAutoscaler):** the Kubernetes controller that adds
  or removes pod copies based on measured CPU load. Configured to scale
  from 2 pods up to 10, triggered at 60% of each pod's own CPU request.
- **Round-robin routing:** K3s's own Service load-balances across every
  ready pod by default, so nothing extra was needed to make it *work*.
  Making it *visible* took one small addition, an NGINX config line
  (`add_header X-Pod-Name $hostname always;`), so every response
  carries the name of the exact pod that answered it.
- **A combined live demo, not two separate ones:** `k6` (load-testing
  tool) driving real traffic in one pane, `k9s` (a terminal dashboard)
  watching the pod count in a second, and a repeating `curl` loop
  reading the `X-Pod-Name` header in a third, all three running at the
  same time.

## Live demo

```bash
k6 run scripts/load-test.js -e TARGET_URL=https://20.229.108.8/
```

![CPU crossing the HPA's target as load ramps up](docs/screenshots/84-cpu-spiking-hpa-triggers-new-pods.png)
*Above: the original 2 pods pushed to 89% and 95% of their CPU request,
with new pods already `ContainerCreating` in response.*

![Four pods running, round-robin proof spanning all of them live](docs/screenshots/85-four-pods-roundrobin-live.png)
*Above: the curl loop cycling through 4 pod names, matching the 4
`hello-world` pods now `Running`, the same scale-up watched from two
angles at once.*

![Peak scale: 6 pods, round-robin proof spanning all of them](docs/screenshots/86-six-pods-roundrobin-peak-scale.png)
*Above: 6 real pod names rotating through the curl loop, genuine
round-robin across a genuinely autoscaled fleet, both proven live at
the same time.*

**Numbers from the actual run:** HPA scaled 2 to 6 replicas under 300
virtual users of real load, roughly 1,457 requests per second at peak.

---

## Incidents along the way

**⚠️ Making round-robin visible broke the rollout.**
Both regional pods served byte-for-byte identical HTML, so a `curl`
loop alone couldn't prove anything. The fix, the `X-Pod-Name` header,
itself triggered a real scheduling problem the moment it deployed: a
new pod sat `Pending` for over half an hour.

![The new pod stuck Pending after the config change](docs/screenshots/78-hello-world-pod-stuck-pending.png)
*Above: two old pods still `Running`, one new pod stuck `Pending`.*

![kubectl describe pod confirming why](docs/screenshots/79-describe-pod-anti-affinity-failure.png)
*Above: "0/2 nodes are available: 2 node(s) didn't match pod
anti-affinity rules", the actual reason, not a guess.*

**What was actually happening:** two settings disagreed with each
other. The Deployment's anti-affinity rule was `required`, a hard rule
that two `hello-world` pods could never share a node, correct for 2
replicas on 2 nodes. The HPA, separately, was allowed to scale up to
10. The moment a rolling update needed a 3rd pod to exist even briefly,
there was no third node for it to land on, and it deadlocked
permanently.

**This is a cost-vs-capacity trade-off, not a design mistake.** The
project's zero-cost constraint keeps the cluster fixed at 2 nodes per
region. In a production system with a real budget, the correct fix is a
**Cluster Autoscaler**, a controller that adds real node capacity when
pods can't schedule. It wasn't built here, for the same reason a
permanent extra node wasn't: it costs real money. The fix that shipped
instead:

- **Changed the rollout strategy** to free a node *before* scheduling a
  replacement, instead of trying to add a third pod first.
- **Softened the anti-affinity rule** from "never" to "strongly prefer,
  but allow if there's no choice", so scaling past node count stacks
  pods rather than deadlocking.

**The honest trade-off:** `required` guarantees losing one node costs
exactly one pod. `preferred` doesn't. If pods end up stacked, one node
failure could take more than one down at once. For a stateless demo app
with no real users, that's a reasonable trade against blocking the HPA
from working at all.

![Both Applications healthy again after the fix](docs/screenshots/81-argocd-both-apps-healthy-again.png)
*Above: both regions back to `Healthy` and `Synced`, the same signal
that caught the problem now confirming it's gone.*

![Two fresh pods, both Running, the stuck one gone](docs/screenshots/82-hello-world-pods-running-after-fix.png)
*Above: two fresh pods, both `1/1 Running`, ages in minutes, not hours.*
