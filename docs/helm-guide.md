# Helm chart

One chart, `helm/petclinic-service/`, deploys any of the eight Petclinic services. ADR-0024. Nothing in this guide is installed.

## Merge order

1. `helm/petclinic-service/values.yaml`
2. `helm-values/{service}.yaml`
3. `helm-values/{env}.yaml`

```bash
helm template config-server helm/petclinic-service/ \
  -n petclinic-dev \
  -f helm-values/config-server.yaml \
  -f helm-values/dev.yaml
```

`scripts/validate-helm.sh` lints the chart and renders all eight services for dev and prod.

## What each file owns

The service file sets the name, port, image name, image tag, Spring profiles, ConfigMap keys, secret refs, and init containers. The API gateway file also sets 200m/1000m CPU.

`dev.yaml` sets one replica, HPA off, and PDB off. `admin-server` is 0 replicas. Rollouts use `maxSurge: 0`. Pass `-n petclinic-dev` (or the ArgoCD destination). The templates do not set `metadata.namespace`.

`prod.yaml` is per-service maps for replicas, HPA, and PDB. It does not turn HPA on for every service. Those counts are inventory. Do not install them on 2× t4g.small. Pass `-n petclinic-prod`.

## Image tag

Each service file has `image.tag: "0000000"`. CI replaces that field with a seven-character commit SHA. Do not use `latest`. The account stays the literal `{account}`. At install, pass both with `--set-string`. The chart coerces them to strings so a numeric account id does not render as `%!s(int64=…)`.

## Add a service

Add `helm-values/{service}.yaml` with `name`, `image.name`, `image.tag`, `service.port`, profiles, and init containers. Point startup probes at `/actuator/health`. If prod should differ from one replica, add keys under `replicaByService`, `autoscalingByService`, and `podDisruptionBudgetByService` in `prod.yaml`. ArgoCD Applications are E-17. Do not add one here.

## Change resources, replicas, or env

Resources and env belong in the service file. Replica, HPA, and PDB belong in the env file. Non-secret settings go under `config` (a ConfigMap). Passwords go under `secretEnv` and must name an existing Secret (`rds-credentials` or `openai-api-key`). Do not put secret values in the values files.

A later `helm upgrade` on a real cluster uses the same `-f` pair. This repo does not run that command.
