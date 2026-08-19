# Failover Runbook

## Scenario A — Azure region fails (Traffic Manager handles automatically)

Expected automatic recovery: ~30 seconds. No action required unless auto-recovery fails.

**Verify auto-recovery:**
```bash
# Watch Traffic Manager endpoint health
watch -n5 az network traffic-manager endpoint show \
  --resource-group rg-ha-platform \
  --profile-name tm-ha-platform \
  --name west-eu --type azureEndpoints \
  --query "properties.endpointStatus"

# Confirm requests hitting second region
curl -s https://your-domain.com | grep "region"
```

**If Traffic Manager does not reroute within 60s:**
```bash
# Manually disable the failed endpoint
az network traffic-manager endpoint update \
  --resource-group rg-ha-platform \
  --profile-name tm-ha-platform \
  --name west-eu --type azureEndpoints \
  --endpoint-status Disabled
```

---

## Scenario B — All Azure fails (Cloudflare routes to Hetzner)

Expected automatic recovery: ~60 seconds. Cloudflare detects Azure origin unhealthy, routes to Hetzner origin pool.

**Verify Hetzner cluster is healthy:**
```bash
KUBECONFIG=~/.kube/hetzner.yaml kubectl get nodes
KUBECONFIG=~/.kube/hetzner.yaml kubectl get pods -A
```

**Verify ArgoCD has synced:**
```bash
KUBECONFIG=~/.kube/hetzner.yaml kubectl -n argocd get applications
```

**If Hetzner cluster is out of sync:**
```bash
KUBECONFIG=~/.kube/hetzner.yaml argocd app sync root --force
```

---

## Scenario C — Azure + Hetzner both unavailable (spin up AWS cold standby)

Trigger the GitHub Actions workflow to provision AWS Frankfurt:

```bash
gh workflow run cold-standby-aws.yml \
  --field region=eu-central-1 \
  --field action=provision
```

Monitor progress:
```bash
gh run watch
```

Expected time to first request served from AWS: ~15 minutes.

After provisioning, update Cloudflare Load Balancing pool manually if automatic health check
has not yet detected the new origin:

```bash
# Update origin IP in Cloudflare (use API or Cloudflare dashboard)
# Pool: tertiary-aws, Origin: <new AWS Load Balancer IP>
```

---

## Velero restore

```bash
# List available backups
velero backup get

# Restore from latest backup
velero restore create --from-backup $(velero backup get -o json | jq -r '.items[0].metadata.name')

# Watch restore progress
velero restore describe --details $(velero restore get -o json | jq -r '.items[0].metadata.name')
```

---

## Uptime Kuma status page

Internal: `http://uptime-kuma.monitoring.svc.cluster.local`
Public: configured per deployment
