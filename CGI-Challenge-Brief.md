# The original CGI brief, verbatim

This is the actual wording from CGI's own challenge document — *"Cloud &
DevOps Challenge"*, an 8-slide PDF CGI sent directly, not a summary or a
paraphrase. It's here so that any claim made anywhere else in this repo can
be checked in one click against exactly what was asked, rather than taken
on trust.

Every quote below is copied as written. The only changes are spacing fixes
where the PDF's own text extraction glued words together (e.g. "asa" →
"as a") — never a change in meaning or wording.

---

## Parameters of the challenge

> "Take the opportunity to demonstrate your skills and talents."

- **Timeframe:** up to 4 days. The clock starts the moment the slide deck
  is received.
- **Research:** "Using the Internet for research is explicitly allowed —
  copying an entire solution is what script kiddies do."
- **Tooling:** "Use whatever technology or tool you are most comfortable
  with (e.g. Ansible, Bash, Python, Terraform, PowerShell or any kind of
  automation tool)."
- **Cloud:** "Azure can be used. If you need an Azure sandbox, please
  contact us."
- **Cost — the literal rule:** "Have fun, and please don't spend any
  money on infrastructure services, domains, or certificates."
- **Deliverable:** "Share git repo or any kind of code. Please prepare a
  short presentation and demo," presented live over MS Teams to Kevin
  Sandermann (Cluster Head & Director), Luca Rodehutskors (Team Manager &
  Lead Architect), Christoph Schlosser (Team Manager), and Raphael Krüger
  (Team Manager).

---

<a id="requirement-1"></a>
## Requirement 1 — Kubernetes cluster

> "Deploy a K8s cluster. The cluster can be deployed on-premises as a
> standalone solution using any provisioner (e.g. Rancher, k3s, kind,
> kube-spray, kubeadm) or as a PaaS solution from a public cloud provider.
> To automate the deployment, Infrastructure as Code (IaC), a script, or a
> playbook should be used. The local machine of the challenge participant
> should be able to connect to the cluster using kubectl, and 'kubectl get
> nodes' should return at least two nodes with the status 'Ready.'"

**Built by:** [requirement-1-kubernetes-cluster.md](requirement-1-kubernetes-cluster.md)

---

<a id="requirement-2"></a>
## Requirement 2 — "Hello World" container

> "A container with any webserver technology should be deployed to the
> cluster. The webserver should be accessible through the challengers'
> browsers and display a simple webpage with a 'Hello World' message."

**Built by:** [requirement-2-hello-world.md](requirement-2-hello-world.md)

---

<a id="requirement-3"></a>
## Requirement 3 — Autoscaling & traffic routing

> "The container should be deployed on multiple nodes, with traffic being
> distributed to the instances according to the round-robin principle. The
> container instances scale automatically based on the CPU load."

**Built by:** [requirement-3-autoscaling-roundrobin.md](requirement-3-autoscaling-roundrobin.md)

---

<a id="requirement-4"></a>
## Requirement 4 — Ingress controller

> "The container should be served via an ingress-controller that
> terminates TLS and returns a valid certificate (self-signed or signed by
> public CA)."

**Built by:** [requirement-4-ingress-tls.md](requirement-4-ingress-tls.md)

---

<a id="requirement-5"></a>
## Requirement 5 — High-available K8s cluster

> "Design a high available scenario for a K8s cluster based on a
> multi-region approach. Traffic routing should be simulated with a
> proxy-server as loadbalancer or with a PaaS cloud-native service. Deploy
> the scenario the same way as part 1 of the challenge."

**Built by:** [requirement-5-multi-region-ha.md](requirement-5-multi-region-ha.md)

---

<a id="requirement-6"></a>
## Requirement 6 — Monitoring concept

> "Describe in high-level terms how you intend to assess the availability
> of the relevant service endpoints of your solution and which
> cloud-native approach might be appropriate."

Note the brief's own wording: this asks for a description, not a specific
tool. It doesn't name Prometheus, Grafana, or any other product — "which
cloud-native approach might be appropriate" is left open.

**Answered by:** [requirement-6-monitoring-concept.md](requirement-6-monitoring-concept.md)

---

<a id="requirement-7"></a>
## Requirement 7 — Backup & Recovery concept

> "Describe in broad strokes how you handle a scenario with two options.
> Zero-down time and a maximum MTTR of 4 hours."

**Answered by:** [requirement-7-backup-recovery-concept.md](requirement-7-backup-recovery-concept.md)

---

<a id="requirement-8"></a>
## Requirement 8 — Infrastructure Debugging

> "Let's assume one of your AKS nodes experiences DNS hiccups. Find a way
> to debug and analyze the network packets on the node. Explain why you
> have chosen this method."

**Answered by:** [requirement-8-dns-debug-runbook.md](requirement-8-dns-debug-runbook.md)

---

**Source:** *Cloud & DevOps Challenge*, CGI Inc., internal slide deck sent
directly to Denis Riungu as the challenge brief.
