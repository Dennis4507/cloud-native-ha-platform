#!/usr/bin/env bash
#
# WHAT THIS SCRIPT DOES
# ----------------------------------------------------------------------------
# Terraform needs somewhere to remember what it has built, and that memory
# (called "state") has to exist before Terraform can create anything else -
# including the very storage account meant to hold it. So this script creates
# that one piece by hand, using the Azure command line directly, before
# Terraform ever runs. By the end of this script, there will be one small,
# dedicated Azure Storage account whose only job is holding that state file,
# safely separated from the resource group Terraform actually manages.
set -euo pipefail

# Deliberately a different resource group from the one Terraform will build
# (rg-ha-platform). Keeping the state storage in its own resource group
# means a future "terraform destroy" of the actual platform can never
# accidentally delete the very record of what to destroy.
RESOURCE_GROUP="rg-tfstate"
LOCATION="westeurope"
CONTAINER_NAME="tfstate"
BACKEND_CONFIG_FILE="terraform/azure/backend-config.hcl"

echo "==> Checking Azure CLI login..."
if ! az account show >/dev/null 2>&1; then
  echo "Not logged in. Run 'az login' first." >&2
  exit 1
fi

# This is the container resource group for the state storage account. It is
# created if it does not already exist, and left alone if it does, so this
# script can safely be run more than once.
echo "==> Ensuring resource group '${RESOURCE_GROUP}' exists..."
if [ "$(az group exists --name "${RESOURCE_GROUP}")" != "true" ]; then
  az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" >/dev/null
fi

# Storage account names have to be unique across the whole of Azure, not
# just this subscription, so a name gets generated once and then reused on
# every later run by reading it back out of the config file this script
# writes at the end. Without this, re-running the script would create a
# second, empty storage account with no history in it, instead of reusing
# the original one.
if [ -f "${BACKEND_CONFIG_FILE}" ]; then
  STORAGE_ACCOUNT="$(grep storage_account_name "${BACKEND_CONFIG_FILE}" | cut -d'"' -f2)"
else
  SUFFIX="$(printf '%04x' "${RANDOM}")"
  STORAGE_ACCOUNT="stcnhptfstate${SUFFIX}"
fi

# This is the actual state storage account. Notice --allow-shared-key-access
# is set to false: this turns off the traditional Azure "account key" login
# method entirely, so there is no password-like secret for this storage
# account at all. Every reader and writer, including Terraform itself, has
# to authenticate as a real, named Azure identity instead - which is exactly
# the "no static credentials anywhere" rule this whole project follows.
echo "==> Ensuring storage account '${STORAGE_ACCOUNT}' exists..."
if ! az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
  az storage account create \
    --name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-blob-public-access false \
    --allow-shared-key-access false \
    >/dev/null
fi

# Blob versioning keeps every past version of the state file, not just the
# latest one. Terraform overwrites this file on every single run, so if a
# run is interrupted partway through (a dropped connection, a Ctrl+C at the
# wrong moment) and corrupts it, versioning means the previous, good copy
# can still be recovered instead of being gone for good.
echo "==> Enabling blob versioning (lets us roll back a bad state write)..."
az storage account blob-service-properties update \
  --account-name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --enable-versioning true \
  >/dev/null

# Note on permissions: this script does not grant itself access to the
# storage account it just created. That happens separately, once, when the
# sandbox identity (cgi-sandbox) is granted the "Storage Blob Data
# Contributor" role through the Azure Portal - deliberately kept outside
# this script, since the sandbox identity only has "Contributor" here, which
# can create and manage resources but cannot grant roles, even to itself.

# The container is the folder-like space inside the storage account where
# the actual state file will live. "--auth-mode login" means this command
# authenticates as whichever identity is signed in via "az login" - it does
# not need or use the account key that was just disabled above.
echo "==> Ensuring blob container '${CONTAINER_NAME}' exists..."
if ! az storage container show --name "${CONTAINER_NAME}" --account-name "${STORAGE_ACCOUNT}" --auth-mode login >/dev/null 2>&1; then
  az storage container create \
    --name "${CONTAINER_NAME}" \
    --account-name "${STORAGE_ACCOUNT}" \
    --auth-mode login \
    >/dev/null
fi

# This file is gitignored - the storage account name is unique to this
# subscription and would break "terraform init" for anyone else who forks
# this repo if it were committed.
echo "==> Writing ${BACKEND_CONFIG_FILE}..."
cat > "${BACKEND_CONFIG_FILE}" <<EOF
resource_group_name  = "${RESOURCE_GROUP}"
storage_account_name = "${STORAGE_ACCOUNT}"
container_name        = "${CONTAINER_NAME}"
key                    = "azure.tfstate"
use_azuread_auth       = true
EOF

echo ""
echo "Done. Next: cd terraform/azure && terraform init -backend-config=backend-config.hcl"
