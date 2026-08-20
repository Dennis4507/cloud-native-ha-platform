#!/usr/bin/env bash
#
# WHAT THIS SCRIPT DOES
# ------------------------------------------------------------------------
# Ansible already copied each cluster's kubeconfig down from its server -
# but K3s writes that file assuming it will only ever be read FROM the
# server itself, so it points at "127.0.0.1" and names everything
# "default" (the cluster, the context, the user - all one entry each,
# because from the server's own point of view there's only ever one of
# it). This script rewrites each file to point at its server's real,
# public address, gives each cluster's entries a name specific to its own
# region, then merges both into one file kubectl can use, with two
# separate, named contexts to switch between.
set -euo pipefail

cd "$(dirname "$0")/.."

# These IPs need to match whatever's currently in ansible/inventory/hosts.yml
# for west-eu-server and germany-west-server. They're written here directly
# rather than read automatically, the same reasoning as the inventory file
# itself: there's no dynamic setup being avoided by hardcoding them, and a
# script that silently trusted a stale value would be worse than one that's
# obviously wrong if these ever change.
WEST_KUBECONFIG="ansible/kubeconfig-west-eu-server.yaml"
GERMANY_KUBECONFIG="ansible/kubeconfig-germany-west-server.yaml"
GCP_KUBECONFIG="ansible/kubeconfig-gcp-showcase.yaml"
WEST_IP="52.236.138.44"
GERMANY_IP="20.52.138.69"
GCP_IP="136.115.185.153"
MERGED_KUBECONFIG="merged-kubeconfig.yaml"

if [ ! -f "${WEST_KUBECONFIG}" ] || [ ! -f "${GERMANY_KUBECONFIG}" ] || [ ! -f "${GCP_KUBECONFIG}" ]; then
  echo "Missing a kubeconfig file - run the Ansible playbook first." >&2
  exit 1
fi

echo "==> Preparing the West Europe kubeconfig..."
sed -e "s/127.0.0.1/${WEST_IP}/" \
    -e "s/default/azure-west/g" \
    "${WEST_KUBECONFIG}" > /tmp/kubeconfig-west-eu.yaml

echo "==> Preparing the Germany West Central kubeconfig..."
sed -e "s/127.0.0.1/${GERMANY_IP}/" \
    -e "s/default/azure-germany-west/g" \
    "${GERMANY_KUBECONFIG}" > /tmp/kubeconfig-germany-west.yaml

# Same rewrite, same reasoning - GCP's own K3s install wrote its kubeconfig
# with the exact same "only ever read from the server itself" assumption
# Azure's did. This is also the proof point of the whole GCP showcase: the
# same script, unmodified, works identically here even though the cluster
# underneath it is on a completely different cloud provider.
echo "==> Preparing the GCP showcase kubeconfig..."
sed -e "s/127.0.0.1/${GCP_IP}/" \
    -e "s/default/gcp-showcase/g" \
    "${GCP_KUBECONFIG}" > /tmp/kubeconfig-gcp-showcase.yaml

# kubectl already knows how to merge multiple kubeconfig files - it just
# needs to be told about more than one at once, through the KUBECONFIG
# environment variable (a colon-separated list, the same idea as PATH).
# "--flatten" is what actually writes out one real, combined file, instead
# of kubectl only merging them freshly in memory each time it happens to run.
echo "==> Merging all three into one kubeconfig..."
KUBECONFIG=/tmp/kubeconfig-west-eu.yaml:/tmp/kubeconfig-germany-west.yaml:/tmp/kubeconfig-gcp-showcase.yaml \
  kubectl config view --flatten > "${MERGED_KUBECONFIG}"

# kubectl doesn't always use ~/.kube/config - if a KUBECONFIG environment
# variable is already set (common when the same machine also runs kubectl
# from native Windows, not just WSL, and both need to share one file),
# that's the real file kubectl reads, and writing anywhere else would be
# invisible to it. This uses that path if it's set, and only falls back to
# the plain default if it isn't.
KUBECONFIG_TARGET="${KUBECONFIG:-${HOME}/.kube/config}"

# Back up whatever is already there instead of silently overwriting it -
# this machine may already have other, unrelated clusters configured.
if [ -f "${KUBECONFIG_TARGET}" ]; then
  cp "${KUBECONFIG_TARGET}" "${KUBECONFIG_TARGET}.bak-$(date +%s)"
  echo "==> Existing kubeconfig at ${KUBECONFIG_TARGET} backed up."
fi

mkdir -p "$(dirname "${KUBECONFIG_TARGET}")"
cp "${MERGED_KUBECONFIG}" "${KUBECONFIG_TARGET}"
echo "==> Written to ${KUBECONFIG_TARGET}"
rm -f /tmp/kubeconfig-west-eu.yaml /tmp/kubeconfig-germany-west.yaml /tmp/kubeconfig-gcp-showcase.yaml

echo ""
echo "Done. Three contexts are now available:"
echo "  kubectl --context azure-west get nodes"
echo "  kubectl --context azure-germany-west get nodes"
echo "  kubectl --context gcp-showcase get nodes"
