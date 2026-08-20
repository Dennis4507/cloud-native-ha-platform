#!/usr/bin/env bash
#
# WHAT THIS SCRIPT DOES
# ------------------------------------------------------------------------
# Simulates West Europe becoming unreachable, live - Requirement 5's
# actual demo. It adds one temporary firewall rule blocking port 80 to
# West Europe from anywhere at all - a genuine regional failure would
# affect everyone, not just the proxy, so this is scoped the same way on
# purpose. That's what makes Uptime Kuma's own West Europe monitor
# actually go red on screen, not just the proxy quietly switching behind
# the scenes. It's also enough on its own to make the NGINX proxy's
# passive health check (max_fails=2, fail_timeout=10s, in
# ansible/roles/proxy/templates/nginx.conf.j2) start routing to Germany
# West Central instead - Germany West Central's own firewall is never
# touched.
#
# Usage:
#   bash scripts/failover-demo.sh break     # simulate the failure
#   bash scripts/failover-demo.sh restore   # undo it
set -euo pipefail

RESOURCE_GROUP="rg-ha-platform"
NSG_NAME="nsg-west-eu"
RULE_NAME="TemporaryBlockWestEuForFailoverDemo"

case "${1:-}" in
  break)
    echo "==> Blocking port 80 to West Europe from anywhere..."
    # A lower priority number than AllowHTTPFromAnywhere's own 120 means
    # this rule is evaluated first - NSG rules are first-match-wins, so
    # this one Deny overrides the broader Allow underneath it.
    az network nsg rule create \
      --resource-group "${RESOURCE_GROUP}" \
      --nsg-name "${NSG_NAME}" \
      --name "${RULE_NAME}" \
      --priority 90 \
      --direction Inbound \
      --access Deny \
      --protocol Tcp \
      --source-address-prefixes "*" \
      --destination-port-ranges 80 \
      --output none
    echo "==> Done. West Europe's Hello World is now unreachable from anywhere -"
    echo "    genuinely down, not just hidden from the proxy."
    echo "    Watch Uptime Kuma's West Europe monitor turn red, then the proxy"
    echo "    (https://136.115.185.153/) start showing Germany West Central instead."
    ;;
  restore)
    echo "==> Removing the temporary block..."
    az network nsg rule delete \
      --resource-group "${RESOURCE_GROUP}" \
      --nsg-name "${NSG_NAME}" \
      --name "${RULE_NAME}"
    echo "==> Done. West Europe is reachable again - the proxy should switch back"
    echo "    to it automatically on its next successful health check."
    ;;
  *)
    echo "Usage: $0 break|restore" >&2
    exit 1
    ;;
esac
