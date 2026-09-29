# Dev startup

Bring up the destroyable dev workload, then Argo CD and the eight Petclinic apps. Profile `petclinic`, region `eu-central-1`. Run from the repo root unless a step says otherwise.

The network stack (VPC, ECR, GitHub OIDC) stays up across sessions. This guide applies the workload stack: NAT, EKS, RDS, and the tainted `t4g.large` for Argo CD.

## Leave the placeholders in git

These strings in `helm-values/` are the committed contract. A new RDS instance gets a new hostname, and the account id must not be committed.

| Placeholder | Files | What it stands for |
|-------------|-------|--------------------|
| `{account}` | `helm/petclinic-service/values.yaml` | AWS account in the ECR image name |
| `0000000` | each `helm-values/{service}.yaml` | Image tag. ECR holds a real seven-character SHA |
| `{rds-endpoint}` | `customers-service.yaml`, `visits-service.yaml`, `vets-service.yaml` | RDS hostname from this apply |

Set all three on the live Argo CD Applications after install. Re-applying `k8s/argocd/applications/dev/` from git clears those settings.

Argo CD clones `https://github.com/agileqatester/petclinic-platform.git` at `main`. The chart and values on that branch are what it deploys. Push this repo before the Applications sync.

Skip `k8s/base/resource-quotas.yaml` and `k8s/base/network-policies/` on this path. The dev quota is 4 CPU, and the published limits already sit over that. Skip the OpenAI ExternalSecret unless you passed an API key at apply.

## 1. Workload

```bash
export AWS_PROFILE=petclinic AWS_REGION=eu-central-1
cd terraform/environments/dev/workload

terraform plan \
  -var-file=terraform.tfvars \
  -var="my_ip=$(curl -s https://checkip.amazonaws.com)/32" \
  -var=enable_argocd=true \
  -out plan.out
terraform apply plan.out
```

Use this new `plan.out`. An older plan does not match the two-flag code.

`enable_observability` stays false. `enable_argocd=true` creates one `t4g.large` and does not install Argo CD or Prometheus.

### Validate

```bash
terraform output -raw rds_endpoint
terraform output -raw eso_role_arn
aws eks describe-cluster --name petclinic-dev --region eu-central-1 \
  --query 'cluster.status' --output text
```

Expect `ACTIVE`, a hostname (no `:3306`), and an ESO role ARN. Then:

```bash
eval "$(terraform output -raw eks_update_kubeconfig)"
kubectl get nodes -L node.kubernetes.io/instance-type,workload
```

Expect three Ready nodes: two `t4g.small` with an empty `workload` label, and one `t4g.large` with `workload=observability`.

`kubectl get nodes --show-labels` needs both dashes. `-show-label` is read as `--server how-label`.

## 2. Namespace and External Secrets

```bash
cd "$(git rev-parse --show-toplevel)"
kubectl apply -f k8s/base/namespaces.yaml

helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set serviceAccount.name=external-secrets-sa \
  --set-string "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=$(terraform -chdir=terraform/environments/dev/workload output -raw eso_role_arn)"
```

The IRSA trust is `external-secrets/external-secrets-sa`. The chart's default ServiceAccount name does not match that, so the `--set serviceAccount.name` is required.

Wait for the webhook, not only the controller. Applying a SecretStore before the webhook has endpoints returns `no endpoints available for service "external-secrets-webhook"`.

```bash
kubectl -n external-secrets rollout status deploy/external-secrets
kubectl -n external-secrets rollout status deploy/external-secrets-webhook
kubectl -n external-secrets rollout status deploy/external-secrets-cert-controller

kubectl apply -f k8s/base/external-secrets/cluster-secret-store.yaml
kubectl apply -f k8s/base/external-secrets/rds-credentials.yaml
```

### Validate

```bash
kubectl get clustersecretstore aws-secrets-manager
kubectl -n petclinic-dev get externalsecret rds-credentials
kubectl -n petclinic-dev get secret rds-credentials -o jsonpath='{.data}' | jq 'keys'
```

Expect the store `Valid`, the ExternalSecret `SecretSynced`, and secret keys `username` and `password`.

## 3. Argo CD

The observability node must be Ready. Argo CD pods tolerate `dedicated=observability:NoSchedule` and will stay Pending on the app nodes.

```bash
kubectl apply -n argocd --server-side --force-conflicts -k k8s/argocd/install
kubectl -n argocd rollout status deploy/argocd-server
kubectl -n argocd rollout status deploy/argocd-repo-server
kubectl -n argocd rollout status statefulset/argocd-application-controller
kubectl apply -n argocd -f k8s/argocd/applications/dev/
```

### Validate the install

```bash
kubectl -n argocd get pods -o wide
kubectl get nodes -l workload=observability -o name
```

Server, repo server, application controller, and Redis should be Running on the `t4g.large`.

## 4. Point the apps at this account, tag, and RDS

Discover the tag that is actually in ECR. Do not type a tag from an old session if the describe comes back empty.

```bash
export AWS_PROFILE=petclinic
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
RDS=$(terraform -chdir=terraform/environments/dev/workload output -raw rds_endpoint)
TAG=$(aws ecr describe-images --repository-name petclinic-dev/config-server --region eu-central-1 \
  --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' --output text)

echo "tag=$TAG host=$RDS"
```

`argocd app set` is a client on your Mac. The server in the cluster does not provide that command. Skip the client and patch the Applications with kubectl:

```bash
export AWS_PROFILE=petclinic
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
RDS=$(terraform -chdir=terraform/environments/dev/workload output -raw rds_endpoint)
TAG=$(aws ecr describe-images --repository-name petclinic-dev/config-server --region eu-central-1 \
  --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' --output text)
JDBC="jdbc:mysql://${RDS}:3306/petclinic?sslMode=REQUIRED"

img=$(jq -n --arg account "$ACCOUNT" --arg tag "$TAG" \
  '[{name:"image.account",value:$account,forceString:true},{name:"image.tag",value:$tag,forceString:true}]')
db=$(jq -n --arg account "$ACCOUNT" --arg tag "$TAG" --arg jdbc "$JDBC" \
  '[{name:"image.account",value:$account,forceString:true},{name:"image.tag",value:$tag,forceString:true},{name:"config.SPRING_DATASOURCE_URL",value:$jdbc,forceString:true}]')

for app in config-server discovery-server api-gateway genai-service admin-server; do
  kubectl -n argocd patch "application/${app}-dev" --type json \
    -p "[{\"op\":\"add\",\"path\":\"/spec/source/helm/parameters\",\"value\":${img}}]"
done
for app in customers-service visits-service vets-service; do
  kubectl -n argocd patch "application/${app}-dev" --type json \
    -p "[{\"op\":\"add\",\"path\":\"/spec/source/helm/parameters\",\"value\":${db}}]"
done
```

If a patch says the path already exists, change `add` to `replace` and run that app again.

The UI and `argocd app list` need the client: `brew install argocd`, then port-forward and log in.

```bash
kubectl -n argocd port-forward svc/argocd-server 8443:443
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
argocd login localhost:8443 --username admin --password "$PASS" --insecure
```

Auto-sync picks up the new parameters. If an app already failed on `{account}` or `{rds-endpoint}`, this next sync replaces the image and the JDBC URL.

### Validate the rendered apps

```bash
kubectl -n argocd get applications
kubectl -n petclinic-dev get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
kubectl -n petclinic-dev get configmap customers-service -o jsonpath='{.data.SPRING_DATASOURCE_URL}{"\n"}'
kubectl -n petclinic-dev get pods
```

Expect:

- Eight Applications. `admin-server` has 0 replicas, so it has no pod.
- Every image is `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-dev/{service}:{tag}` with the real account and `$TAG`. No `{account}` and no `0000000`.
- The customers ConfigMap URL contains `$RDS`, not `{rds-endpoint}`.
- Seven app pods reach `1/1` on the `t4g.small` nodes. Argo CD pods stay on the large node.

Config Server and Discovery Server must be Ready before the other pods pass their init containers. A few minutes of `Init` is that wait.

## 5. Smoke

```bash
kubectl -n petclinic-dev port-forward svc/api-gateway 8080:8080
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/api/vet/vets
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/api/customer/owners
```

Expect `200` from both once customers and vets are Ready.

## Stop the session

From `terraform/environments/dev/workload`. ECR stays. The large node and the rest of the workload go away.

```bash
export AWS_PROFILE=petclinic
terraform destroy \
  -var-file=terraform.tfvars \
  -var="my_ip=$(curl -s https://checkip.amazonaws.com)/32"
```

Destroy fails if `my_ip` is omitted. Apply again with both flags false if you only want the `t4g.large` removed and the cluster kept.
