#!/usr/bin/env bash
# Print the generated Grafana admin password from the cluster Secret.
set -euo pipefail
kubectl -n monitoring get secret monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
echo
