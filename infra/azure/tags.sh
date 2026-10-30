#!/usr/bin/env bash
# Re-applies the required tags (CLAUDE.md) to every resource in the resource group. Rerunnable; merge keeps other tags.
set -euo pipefail
source "$(dirname "$0")/env.sh"
for id in $(az resource list -g "$RG" --query "[].id" -o tsv); do
  az tag update --resource-id "$id" --operation merge --tags $TAGS -o none && echo "tagged ${id##*/}"
done
