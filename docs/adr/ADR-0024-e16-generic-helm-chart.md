# ADR-0024: E-16 generic Helm chart and env values (git only)

**Status:** Accepted
**Date:** 2026-09-23
**Context:** Epic E-16 (`PETPLAT-107`–`111`) is the workload packaging for the eight Spring services. ADR-0018 left Deployments, Services, ConfigMaps, ServiceAccounts, probes, JDBC env, and init containers to Helm. ADR-0019 froze replica, HPA, and PDB numbers for `helm-values/{dev,prod}.yaml`. ADR-0023 caps the app namespaces at CPU 4 and memory 4Gi for both requests and limits; the published container sizes do not admit. PETPLAT-101 splits securityContext: pod fields once, container fields on the app container and each init container, `readOnlyRootFilesystem: false`, no `NET_BIND_SERVICE`, PSA enforce stays `baseline`. ExternalSecrets `rds-credentials` and `openai-api-key` already exist and are referenced, not recreated. `helm/zipkin` and `helm-values/observability/` stay out of scope. No `helm install`, no `kubectl apply`, no ALB, no ArgoCD Applications.

**Decision:** One generic chart, `helm/petclinic-service/`, plus eight service values files and `helm-values/dev.yaml` and `helm-values/prod.yaml`. Render with `helm lint` and `helm template`. Do not install.

### Values merge

Chart `values.yaml`, then `helm-values/{service}.yaml`, then `helm-values/{env}.yaml`.

`dev.yaml` sets `image.env: dev`, `replicaCount: 1`, HPA off, PDB off. `admin-server` is `replicaByService: 0` because eight JVMs do not fit on 2× t4g.small once a DaemonSet (Fluent Bit, node exporter) is on every node. Dev rollouts use `maxSurge: 0`. The release namespace comes from `helm -n` or the ArgoCD destination (`petclinic-dev`), not from a `metadata.namespace` in the templates. The image helper prints account and tag with `toString`, because Helm `--set` stores a 12-digit account id as a number.

`prod.yaml` does not set a flat replica count of 2. It uses maps keyed by service name:

- `replicaByService`: config, discovery, api-gateway, customers, visits, and vets at 2. genai and admin at 1.
- `autoscalingByService`: api-gateway 2–6 at 70% CPU. customers, visits, and vets 2–4 at 70%. genai 1–3 at 70%. Others stay off.
- `podDisruptionBudgetByService`: `minAvailable: 1` for config, discovery, api-gateway, customers, visits, and vets. No PDB for genai or admin.

If a map has no key for the service, the chart uses `replicaCount`, `autoscaling.enabled`, and `podDisruptionBudget.enabled`.

### Services

| Service | Port | Profiles | Init containers |
|---------|------|----------|-----------------|
| config-server | 8888 | `docker` | none |
| discovery-server | 8761 | `docker` | config |
| api-gateway | 8080 | `docker` | config, discovery |
| customers-service | 8081 | `docker,mysql` | config, discovery |
| visits-service | 8082 | `docker,mysql` | config, discovery |
| vets-service | 8083 | `docker,mysql` | config, discovery |
| genai-service | 8084 | `docker` | config, discovery |
| admin-server | 9090 | `docker` | config, discovery |

api-gateway CPU is 200m/1000m. Every other service is 100m/500m and 128Mi/512Mi. Init containers use 100m/128Mi and 500m/512Mi so they do not add a second 512Mi to the pod quota.

Customers, visits, and vets read `username` and `password` from Secret `rds-credentials`. JDBC URL host is the placeholder `{rds-endpoint}`. genai reads `OPENAI_API_KEY` from Secret `openai-api-key` with `optional: true`. Config Server Git URI is `https://github.com/spring-petclinic/spring-petclinic-microservices-config` (`SPRING_CLOUD_CONFIG_SERVER_GIT_URI` and `GIT_REPO`). The `native` profile stays off.

Image reference: `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/{service}:0000000`. Tag placeholder `0000000` is seven hex characters so the tag workflow can replace `.image.tag`. Never `latest`. Never a real account ID.

### Probes and security

Startup path is `/actuator/health` for every service (period 10s, failure threshold 30). Readiness is `/actuator/health/readiness` and liveness is `/actuator/health/liveness`, except Config Server, which uses `/actuator/health` for all three. `initialDelaySeconds` is 0.

Pod securityContext: `runAsNonRoot`, `runAsUser` 1000, `fsGroup` 1000, `seccompProfile: RuntimeDefault`. The same container securityContext is on the app container and each init container: `allowPrivilegeEscalation: false`, drop ALL, `readOnlyRootFilesystem: false`, `seccompProfile: RuntimeDefault`. App ServiceAccounts have no IRSA annotation.

`scripts/validate-helm.sh` runs lint and the 16 templates. It does not call a cluster. `docs/helm-guide.md` records merge order and how to add a service. ArgoCD Applications stay in E-17.

**Consequences:**
- Positive: One chart for all eight services. CI can update `.image.tag` once the files exist. Cost is about $0 until install.
- Negative: A full install still fails the ADR-0023 CPU limit (4500m vs 4) and prod memory limits (7Gi vs 4Gi). Prod ExternalSecrets are not authored. JDBC host and image tag `0000000` are placeholders.
- Security: No secret values in git. No app IRSA. PSA enforce stays `baseline`.

**Rejected:** Eight charts. Kustomize. `helm install` or ArgoCD in this epic. A flat prod replica count of 2. Raising the quota or shrinking containers. IRSA on app ServiceAccounts. `latest` or an empty tag. A private config-repo URL. Discovery waiting on itself. Visits waiting on customers.
