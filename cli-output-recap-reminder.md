# CLI output recap - a reminder, not a lesson

This is a reminder file, not a teaching file - everything in here is
already understood, this just exists so nothing gets forgotten in the
moment when a screenshot is on screen and a question comes in about it.

**How to use this during the presentation:** the table below lists every
terminal screenshot in the README, in the exact order they appear there -
which is also the order they'd naturally come up walking through a demo.
Follow it top to bottom. Keep this file open on a second screen, scrolled
to whichever numbered section a row points to, so switching to it takes a
glance, not a search.

## Screenshot order

Each entry: the command that produced it, what's actually on screen, and
which section (if any) to have open.

**1. `05-bootstrap-tfstate-done`**
Command: `bash scripts/bootstrap-tfstate.sh`
Shows: the one-time state-storage setup script running.
Reference: plain script messages, no jargon.

**2. `06-terraform-init-success`**
Command: `terraform init -backend-config=backend-config.hcl`
Shows: "Terraform has been successfully initialized!"
Reference: [§1 Terraform](#1-terraforms-plan-and-apply-output).

**3. `07-terraform-plan-clean`**
Command: `terraform plan`
Shows: "Plan: 22 to add, 0 to change, 0 to destroy."
Reference: [§1 Terraform](#1-terraforms-plan-and-apply-output).

**4. `11-apply-rg-conflict`**
Command: `terraform apply`
Shows: the resource group already exists error.
Reference: [§1 Terraform](#1-terraforms-plan-and-apply-output).

**5. `12-import-successful`**
Command: `terraform import azurerm_resource_group.main /subscriptions/.../resourceGroups/rg-ha-platform`
Shows: "Import successful!"
Reference: [§1 Terraform](#1-terraforms-plan-and-apply-output).

**6. `13-ephemeral-disk-error`**
Command: `terraform apply`
Shows: the ephemeral-disk size error on the two virtual machine scale sets.
Reference: [§1 Terraform](#1-terraforms-plan-and-apply-output).

**7. `15-sku-not-available-error`**
Command: `terraform apply`
Shows: "SkuNotAvailable" - capacity restriction error, both regions at once.
Reference: [§1 Terraform](#1-terraforms-plan-and-apply-output).

**8. `16-sku-catalog-investigation`**
Command: `az rest --method get --url "https://management.azure.com/subscriptions/<id>/providers/Microsoft.Compute/skus?api-version=2021-07-01" --query "value[?resourceType=='virtualMachines' && (name=='Standard_B2s_v2' || name=='Standard_B2as_v2' || name=='Standard_D2s_v5')].{Name:name,Locations:locations,Restrictions:restrictions}" -o json`
Shows: raw JSON from Azure's own SKU catalog, confirming the region restriction.
Reference: self-explanatory - the `reasonCode` field says it plainly.

**9. `17-d2sv3-confirmed-germany-west`**
Command: `az vm create --resource-group rg-ha-platform --name sku-test-d2sv3 --location germanywestcentral --size Standard_D2s_v3 --image Ubuntu2204 --admin-username azureuser --generate-ssh-keys`
Shows: the throwaway test VM, `"powerState": "VM running"`.
Reference: self-explanatory.

**10. `18-apply-complete`**
Command: `terraform apply`
Shows: "Apply complete! Resources: 11 added, 0 changed, 9 destroyed" - the region swap taking effect.
Reference: [§1 Terraform](#1-terraforms-plan-and-apply-output).

**11. `20-instance-public-ips`**
Command: `az vmss list-instance-public-ips --resource-group rg-ha-platform --name vmss-west-eu -o table` (and the same for `vmss-germany-west`)
Shows: each virtual machine's own public IP address, in a plain table.
Reference: self-explanatory.

**12. `24-ansible-ping-success`**
Command: `ansible all -i inventory/hosts.yml -m ping`
Shows: all four machines responding `"ping": "pong"`.
Reference: self-explanatory - success or failure, per host.

**13. `25-k3s-join-hang`**
Command: `ssh -i ~/.ssh/id_rsa_azure azureuser@<agent-ip> "sudo systemctl status k3s-agent --no-pager"`
Shows: the service stuck mid-start, never finishing.
Reference: [§2 systemctl](#2-systemctl-status-service).

**14. `27-tcp-connection-blocked`**
Command: `ssh -i ~/.ssh/id_rsa_azure azureuser@<agent-ip> "timeout 5 bash -c 'cat < /dev/null > /dev/tcp/<server-ip>/6443' && echo CONNECTED || echo BLOCKED"`
Shows: a direct, one-line connectivity test - `BLOCKED`.
Reference: self-explanatory.

**15. `28-both-clusters-ready`**
Command: `ansible-playbook -i inventory/hosts.yml playbook.yml`, followed by `ssh -i ~/.ssh/id_rsa_azure azureuser@<server-ip> "sudo k3s kubectl get nodes"` for each region.
Shows: the PLAY RECAP, then both regions showing two `Ready` nodes - confirmed from inside each cluster, over SSH, not yet from the laptop itself.
Reference: [§3 Ansible](#3-ansibles-play-recap-line) + [§4 kubectl](#4-kubectl-get-nodes).

**16. `29-kubeconfig-context-not-found`**
Command: `kubectl config get-contexts`, after running `bash scripts/kubeconfig-merge.sh`.
Shows: only one generic `default` context exists, even though the merge script reported success.
Reference: self-explanatory - the merge script's own "done" messages were misleading here, worth remembering if asked why this wasn't caught immediately.

**17. `30-kubeconfig-env-var-fix`**
Command: `echo $KUBECONFIG`, then `bash scripts/kubeconfig-merge.sh` re-run, then `kubectl config get-contexts`.
Shows: the environment variable pointing at a Windows-side path this laptop already had set; both real contexts appear once the script is fixed to respect it; a new TLS error appears immediately underneath.
Reference: self-explanatory.

**18. `31-tls-san-both-regions-error`**
Command: `kubectl --context azure-west get nodes` and `kubectl --context azure-germany-west get nodes`.
Shows: both clusters rejecting the connection - `x509: certificate is valid for <private IP>, ... not <public IP>`.
Reference: self-explanatory - each error names the addresses the certificate actually covers.

**19. `32-k3s-clean-uninstall-confirmed`**
Command: `command -v k3s || echo 'k3s gone'` and `systemctl status k3s` (or `k3s-agent`), run against all four machines.
Shows: the k3s binary and its systemd service both fully removed on every node, before the rebuild.
Reference: self-explanatory.

**20. `33-kubectl-both-clusters-ready-from-laptop`**
Command: `ansible-playbook -i inventory/hosts.yml playbook.yml`, then `bash scripts/kubeconfig-merge.sh`, then `kubectl --context azure-west get nodes` and `kubectl --context azure-germany-west get nodes`.
Shows: the full rebuild, then both clusters showing two `Ready` nodes each - this time reached directly from the laptop, no SSH involved. This is Requirement 1, satisfied exactly as the brief asks for it.
Reference: [§3 Ansible](#3-ansibles-play-recap-line) + [§4 kubectl](#4-kubectl-get-nodes).

**21. `34-argocd-pods-running`**
Command: `kubectl --context azure-west get pods -n argocd`, after installing with `--server-side`.
Shows: all seven ArgoCD pods `Running`.
Reference: self-explanatory.

**22. `35-cert-manager-missing-error`**
Command: `argocd app get hello-world-west-eu`, before cert-manager was installed on either cluster.
Shows: `SyncError` naming the exact missing piece - "Make sure the 'Certificate' CRD is installed on the destination cluster."
Reference: self-explanatory.

**23. `36-cert-manager-installed-both-clusters`**
Command: `kubectl --context azure-west get pods -n cert-manager` and the same for `azure-germany-west`.
Shows: three cert-manager pods per cluster, `Running` - the dependency that was missing when the first sync attempt failed.
Reference: self-explanatory.

**24. `37-west-eu-synced-healthy`** / **25. `38-germany-west-synced-healthy`**
Command: `argocd app sync hello-world-west-eu` / `hello-world-germany-west`, then `argocd app get` for each.
Shows: every resource ArgoCD manages for that region - `Synced` and `Healthy`.
Reference: self-explanatory.

**26. `39-hello-world-west-eu-https`** / **27. `40-hello-world-germany-west-https`**
Command: browser, `https://20.229.108.8/` and `https://20.218.111.44/`.
Shows: Hello World, live, each region's own identity text, over HTTPS.
Reference: self-explanatory.

**28. `41-argocd-ui-login`**
Command: browser, `https://localhost:8080` (through the `kubectl port-forward` tunnel).
Shows: ArgoCD's own login page - proof the GitOps dashboard itself is reachable, not just the CLI.
Reference: self-explanatory.

**29. `42-traefik-default-cert-bug`**
Command: browser certificate viewer, clicking the "Not secure" warning on either region's Hello World page.
Shows: `TRAEFIK DEFAULT CERT` - the wrong certificate, before the `TLSStore` fix.
Reference: self-explanatory - worth having this one ready specifically because it looks like nothing's wrong until this exact screen is checked.

**30. `43-real-cert-west-eu-fixed`** / **31. `44-real-cert-germany-west-fixed`**
Command: same certificate viewer, after applying the `TLSStore` fix and re-syncing.
Shows: the real certificate this time - issued at the exact second cert-manager created it, valid for roughly 90 days.
Reference: self-explanatory.

Most of these need no glossary at all - they already say what happened in
plain words. The four sections below are for the handful of rows where the
output uses a specific vocabulary worth having ready.

## 1. Terraform's plan and apply output

![A clean Terraform plan](docs/screenshots/07-terraform-plan-clean.png)
*The summary line at the bottom - "Plan: X to add, Y to change, Z to
destroy" - is the one line worth reading first, every time.*

```
+ create      # doesn't exist yet, will be created
- destroy     # exists, will be deleted
~ update in-place   # exists, a setting changes without deleting it
-/+ destroy and then create replacement
              # a setting changed that Azure can't update in-place
              # (like a VM's network config) - deleted and rebuilt, not adjusted
```

"Change" in the summary line always means an in-place update (`~`), never
a delete. A resource being destroyed *and* recreated (`-/+`) counts once
in "to add" and once in "to destroy," never in "to change."

## 2. `systemctl status <service>`

![A service stuck "activating" instead of running](docs/screenshots/25-k3s-join-hang.png)
*The line to notice is `Active: activating (start)`, not `active
(running)`.*

- **Active: active (running)** - healthy, working normally.
- **Active: activating (start)** - still starting up, or stuck trying to.
  Past a minute or two, something's wrong - this is exactly what this
  screenshot caught.
- **Main PID** - the process ID of the running service. Worth checking
  after a fix - if the PID hasn't changed, the old, unfixed process is
  still the one running, not a fresh one.

## 3. Ansible's PLAY RECAP line

![A real PLAY RECAP, with an actual kubectl result underneath it](docs/screenshots/28-both-clusters-ready.png)
*The recap line is the top half of this shot; `kubectl get nodes` is the
bottom half, covered in the next section.*

```
west-eu-agent : ok=9  changed=2  unreachable=0  failed=0  skipped=0  rescued=0  ignored=0
```

Each number counts *tasks*, not machines, across the whole run on that one
machine:

- **ok** - the task ran and the end state was already correct, or became
  correct. Almost always the largest number, and that's expected.
- **changed** - the task actually *did* something (installed a package,
  wrote a file). Re-running the same playbook later, most tasks report
  "ok" without "changed" - there's nothing left to do.
- **unreachable** - Ansible couldn't even connect to the machine (network
  or SSH problem). Zero means every connection attempt succeeded.
- **failed** - Ansible connected fine, ran the task, and the task itself
  errored. Zero means nothing broke.
- **skipped** - a task was deliberately not run because its condition
  wasn't met - almost always the "is this already installed?" check
  correctly deciding not to redo something. Not a problem; idempotency
  working as intended.
- **rescued** / **ignored** - both relate to Ansible's error-handling
  features (a failure being deliberately caught, or deliberately allowed
  without stopping the run). Neither feature is used in this project, so
  both are always 0 - expected, not a gap.

## 4. `kubectl get nodes` / `k3s kubectl get nodes`

*(Same screenshot as section 3 above - the bottom half of it.)*

```
NAME                 STATUS   ROLES           AGE   VERSION
vmss-west-eu000000   Ready    control-plane   61m   v1.36.3+k3s1
vmss-west-eu000005   Ready    <none>          76s   v1.36.3+k3s1
```

- **STATUS: Ready** - the node is healthy and able to run workloads.
- **ROLES: control-plane** is the server node (runs the Kubernetes API);
  **`<none>`** is a worker node. `<none>` is the normal, expected value
  for a worker, not a missing label.
- **AGE** is how long the node has existed, not how long it's been
  healthy.
- **VERSION** should match across every node - a mismatch would mean
  nodes were installed at different times with different versions.

## 5. Files that appear on disk during the demo, not just terminal output

Running the actual commands doesn't just print things - it leaves real
files behind in the project folder, visible in VS Code's file explorer or
a plain `ls`. None of these are hand-written; they're every one of them a
side effect of a command that already ran. Worth knowing what each one is
and why it looks the way it does, in case a panel member points at the
file tree mid-demo and asks - that shouldn't be a moment spent
reconstructing the answer live.

**`ansible/kubeconfig-<hostname>.yaml`** (one per server: `west-eu-server`,
`germany-west-server`, `gcp-showcase`)
Created by: the `k3s-server` Ansible role's last step, which copies K3s's
own generated kubeconfig down to this laptop.
Why it looks the way it does: K3s writes this file assuming it will only
ever be read *from the server itself* - so it points at `127.0.0.1`, and
names the cluster, context, and user all `default`, because from the
server's own point of view there's only ever one of each.
Why it's not in the repo: this is a live, working credential - the actual
client certificate and private key needed to fully administer that
specific cluster. Committing it would hand out real access to whoever
found it. (This is also the exact mistake caught and fixed early in the
build - see README's incident on it.)

**`merged-kubeconfig.yaml`** (project root)
Created by: `scripts/kubeconfig-merge.sh`, right before it copies the
result to wherever `kubectl` actually reads from.
Why it looks the way it does: this is the three raw per-server kubeconfigs
above, rewritten (each `127.0.0.1` replaced with that server's real public
IP, each `default` renamed to a region-specific context name) and merged
into one file with three named, switchable contexts.
Why it's not in the repo: same reason as the files above - still real
credentials, just combined into one file instead of three.

**`~/.kube/config` (or wherever `$KUBECONFIG` points)**
Created by: the last step of `kubeconfig-merge.sh`, and it's not inside
this project folder at all - it's the actual file `kubectl` itself reads
by default, system-wide, for every project on this machine, not just this
one.
Why there might be `.bak-<timestamp>` copies sitting next to it: the merge
script backs up whatever was already there before overwriting it, every
single time it runs - deliberately, so a first run on a machine that
already had other clusters configured doesn't silently destroy that
configuration. These backups are safe to ignore, or delete, at any time.

**`terraform/azure/.terraform/` and `terraform/gcp/.terraform/`**
Created by: `terraform init`.
What it is: the downloaded provider plugin itself (the actual code that
knows how to talk to Azure's or GCP's API) - large (the Azure one alone is
over 200MB), entirely regenerable by re-running `init`, and not something
any two people working on this project would even want to keep in sync
manually.

**`terraform/azure/backend-config.hcl`**
Created by: `scripts/bootstrap-tfstate.sh`, once, the very first time this
project's remote state storage was set up.
Why it's not in the repo: it holds the real storage account name Terraform
state lives in - specific to this exact Azure subscription, not something
that would even work if copied into a different one, and not something
that needs to be secret so much as pointless to share.
