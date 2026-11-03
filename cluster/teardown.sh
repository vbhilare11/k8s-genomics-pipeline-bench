#!/usr/bin/env bash
# Remove everything bootstrap.sh installed. Destructive.
set -euo pipefail
helm -n keda uninstall keda || true
helm -n monitoring uninstall monitoring || true
kubectl delete namespace keda monitoring --ignore-not-found
if command -v k3s-uninstall.sh >/dev/null 2>&1; then
  k3s-uninstall.sh
fi
