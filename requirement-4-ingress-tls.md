# Requirement 4: Ingress controller with TLS

> CGI's brief: *"The container should be served via an ingress-controller
> that terminates TLS and returns a valid certificate (self-signed or
> signed by public CA)."*
>
> [Verify against the full brief →](CGI-Challenge-Brief.md#requirement-4)

**In short:** Traefik (built into K3s) terminates HTTPS, and
cert-manager issues a self-signed certificate automatically, explicitly
allowed by the brief's own wording. Live and verified in a browser on
both regions.

## What I built

- **Traefik**, K3s's built-in ingress controller. No separate install
  is needed, and it terminates TLS ("Transport Layer Security," the
  encryption behind `https://`) at the edge, before traffic reaches the
  application.
- **cert-manager**, with a `SelfSigned` `ClusterIssuer`. Self-signed
  certificates are explicitly acceptable per the brief. A
  publicly-signed one would need a real registered domain, which the
  brief's own "no domain" rule rules out.
- **One `Certificate` resource per region**, each requesting its own
  certificate through the shared `ClusterIssuer`.

## Live demo

- **West Europe:** `https://20.229.108.8/`
- **Germany West Central:** `https://20.218.111.44/`

![Hello World, live over HTTPS, West Europe](docs/screenshots/39-hello-world-west-eu-https.png)
*Above: a real certificate, terminated by Traefik, in front of the
application.*

---

## Incidents along the way

**⚠️ Every command-line check said the certificate was fine. It
wasn't.** `kubectl get certificate` showed the object as `Ready`, and
ArgoCD's own dashboard marked the whole application `Healthy`. Both
checks were only confirming that cert-manager had successfully *issued*
a certificate somewhere, not which certificate the browser would
actually receive. I only found the mismatch by opening the site itself:
the certificate the browser presented (screenshot below) was Traefik's
own generic built-in one, not the real certificate cert-manager had
issued.

![The wrong certificate, Traefik's generic default, not the real one](docs/screenshots/42-traefik-default-cert-bug.png)
*Above: "TRAEFIK DEFAULT CERT", technically a certificate, just not the
one this project actually built.*

**What was actually happening:** Traefik decides which certificate to
present using SNI ("Server Name Indication," the hostname a browser
sends during the TLS handshake, before it even asks for a page),
matched against the hostnames configured on each Ingress. This project
deliberately has no hostname, raw IPs only, per the "no domain" rule, so
Traefik had nothing to match against and silently fell back to its own
default instead of erroring. The real certificate was never broken;
Traefik simply never knew to offer it.

**Fix:** a `TLSStore`, one of Traefik's own resource types, naming a
specific certificate as the *default*, used whenever no more specific
rule matches. One per region, since each runs its own separate Traefik
instance.

![The real certificate, confirmed on both regions](docs/screenshots/43-real-cert-west-eu-fixed.png)
*Above: issued at the exact second cert-manager created it, genuinely
the right certificate this time, not just a status field claiming so.*

![The same fix, confirmed on Germany West Central too](docs/screenshots/44-real-cert-germany-west-fixed.png)
*Above: the same result, independently, for the second region.*
