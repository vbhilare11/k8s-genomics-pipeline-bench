# Cluster bootstrap

Single-node [k3s](https://k3s.io) with
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
and [KEDA](https://keda.sh). Target: Ubuntu 24.04, 4 vCPU / 8 GB.

## Install

```bash
sudo ./bootstrap.sh
```

Idempotent. Pin versions for an exact reproduction:

```bash
sudo K3S_VERSION=v1.31.4+k3s1 KPS_CHART_VERSION=66.3.1 KEDA_CHART_VERSION=2.16.1 ./bootstrap.sh
```

The versions actually installed are recorded in `versions.lock`; the paper cites that file.

## Credentials

The Grafana admin password is generated at install time and lives only in the
`monitoring/monitoring-grafana` Secret. It is never written to this repository.

```bash
./grafana-password.sh
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

## Verify

```bash
kubectl get pods -A | grep -Ev 'Running|Completed'   # expect header line only
kubectl top nodes
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
curl -s 'http://localhost:9090/api/v1/query?query=up' | head -c 200
```

## Remove

```bash
sudo ./teardown.sh
```

## Design notes

- Traefik is disabled; the benchmark exposes nothing publicly.
- Alertmanager is disabled; alerting is out of scope for the measurements.
- 15 s scrape interval and 30 d retention give sub-minute resolution on scaling
  events across a full experiment campaign.
