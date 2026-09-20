# ADR-0016: Skip Route 53/ACM without a domain; LBC waits on EKS

**Status:** Accepted
**Date:** 2026-09-20
**Context:** Epic E-6, **dev only**. Same locked intent as ADR-0015. E-6 is blocked by E-3 for **Load Balancer Controller and Ingress apply**. Network already has public subnets tagged `kubernetes.io/role/elb=1`, private `internal-elb=1`, and an ALB SG (80/443 `0.0.0.0/0`, egress to node SG :8080). Spec DNS section assumes `{domain}`, a public hosted zone, ACM wildcard with Route 53 validation, and `petclinic-dev.{domain}` alias to the ALB. This repo has **no registered domain**. `aws_acm_certificate_validation` will wait forever if NS are not delegated at a registrar.

Keep vs destroy is three different SKUs:
- **Public hosted zone:** $0.50/month always-on (global). Recreating it breaks NS delegation. **Keep** — *if* you own a domain.
- **ACM public cert:** **$0**. Lives with the zone. **Keep** with the zone.
- **ALB:** Frankfurt **$0.027/hour** (~$20/month 24/7) + **$0.008/LCU-hour**. Created by LBC from Ingress, not a Terraform `aws_lb`. **Destroy** with the cluster. Free-tier ALB hours exist for new accounts; do not treat 24/7 as $0.

saas-ntier-lab puts ALB/LBC in **workload**. Default lab edge is HTTP to `my_ip` `/32` and **no Route 53**. Their optional alias is on the ALB module, not a keep-stack zone. Petclinic ALB stays internet-facing `0.0.0.0/0` (ADR-0001). LBC `target-type: ip`, ClusterIP services, path `/` → api-gateway:8080 — unchanged.

LBC IRSA trust needs the cluster OIDC issuer. Helm install needs a Ready cluster. Neither can run until E-3 is applied.

**Decision:** Treat a **real, delegated domain as optional**. Default for this learning account: **do not create** a public hosted zone and **do not request** ACM. Do not hang apply on certificate validation. Reach the app later via the ALB DNS name over **HTTP**.

Split E-6:

| Piece | Keep vs destroy | When |
|--------|-----------------|------|
| `terraform/modules/dns/` (zone + ACM + DNS validation records) | **Keep**, network root | **Code now.** Call from `environments/dev/network` only if `domain_name` is non-empty (variable/tfvars, never invent `example.com` as a live zone). Empty → `count = 0`, plan shows nothing. |
| ACM wildcard `*.{domain}` in **eu-central-1** (ALB region, not us-east-1) | Keep with zone | Only with a delegated domain. |
| Route 53 alias `petclinic-dev.{domain}` → ALB | Cheap; needs live ALB | **Wait** for LBC-created ALB (PETPLAT-31). |
| LBC IAM policy + IRSA role | IAM $0; OIDC dies with cluster → **workload** | **Code** policy JSON / role HCL now; **apply/install waits on E-3**. |
| Helm `aws-load-balancer-controller` in `kube-system`, IngressClass `alb` | Destroy with cluster | **Wait** on E-3 apply (PETPLAT-29). Helm CLI as the story says; do not add `helm_release` to network. |
| Ingress YAML (`k8s/base/ingress/ingress.yaml`) | Git only until apply | **Write now:** `ingressClassName: alb`, internet-facing, `target-type: ip`, `/` → api-gateway:8080, health `/actuator/health` on 8080. **Omit** `certificate-arn` and `ssl-redirect` until ACM exists. **Do not apply** (no controller). |
| ALB | Destroy | Created by LBC after Ingress apply; public subnets. |

Skip prod. Skip E-3 apply, so skip PETPLAT-29/30/31 **apply** this epic. PETPLAT-32 wire is a gated `count` in **network**, not workload (zone is keep-shaped). Do not put the zone in workload: destroy would drop NS and the $0.50 bill would be the wrong reason to recreate a zone.

When a domain exists later: set `domain_name`, apply **network**, complete ACM DNS validation, then add the cert annotation and alias after ALB exists. Registrar NS setup is a human step outside Terraform.

**Consequences:**
- Positive: No $0.50/month empty zone. No stuck ACM validation. Learning HTTPS is not fake-validated. LBC/ALB stay in the destroy habit (~$0.027/h while the session is up). Ingress YAML and the dns module can be reviewed without EKS. Matches saas “HTTP ALB, Route 53 optional.”
- Negative: Spec’s wildcard HTTPS and pretty hostname are **deferred**. Browser traffic is HTTP to `*.elb.amazonaws.com` until a domain exists. ALB SG already opens 443; unused until ACM. First workload apply still does not install LBC unless E-3 apply is explicitly opened later. Alias cannot be applied without both a zone and an ALB DNS name (chicken-egg is real).
- Rejected — always create a public zone for `example.com` / placeholder: $0.50/month, undelegated NS, ACM never ISSUED, teaches a broken DNS lab.
- Rejected — private hosted zone: does not validate public ACM and does not name a public ALB.
- Rejected — HTTP→HTTPS redirect without a cert: ALB listener 443 would be broken.
- Rejected — Terraform `aws_lb` instead of LBC: fights Ingress/GitOps; saas Phase A is controller-driven.
- Rejected — LBC/IRSA in network: OIDC URL comes from the cluster; keep-stack IAM would dangle after workload destroy.
- Rejected — third root for DNS: zone is either skip or keep-with-VPC/ECR.
- Rejected — NLB, CloudFront, us-east-1 cert: extra SKUs; ALB + regional ACM is the spec.

**Still applies after accept:** PETPLAT-28 (**module code**; validation AC only when `domain_name` is real), PETPLAT-30 (**write** Ingress YAML, HTTP-first; skip apply), PETPLAT-32 (**gated wire** in **dev/network**). PETPLAT-29: **author** IAM policy + Helm values; **install/verify blocked** on E-3 apply. PETPLAT-31 blocked on domain + live ALB. **Skip** PETPLAT-29/30/31/32 apply this epic. IRSA for LBC remains the spec role `petclinic-dev-lb-controller-role` when E-3 is applied. ADR-0001 ALB-in-public-subnets unchanged.
