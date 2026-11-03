# Cluster bootstrap

```bash
./bootstrap.sh
```

Installs k3s (Traefik disabled), kube-prometheus-stack (Grafana password `lab`, 15s scrape,
30d retention, Alertmanager off) and KEDA. Verify:

```bash
kubectl get pods -A | grep -v Running | grep -v Completed   # expect header only
kubectl top nodes
```
