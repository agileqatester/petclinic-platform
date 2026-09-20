# AWS Load Balancer Controller IRSA (PETPLAT-29). Helm install waits on E-3 apply.

data "aws_iam_policy_document" "lbc_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lbc" {
  name               = "${var.project}-${var.environment}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lbc_assume.json

  tags = {
    Name = "${var.project}-${var.environment}-lb-controller-role"
  }
}

resource "aws_iam_policy" "lbc" {
  # checkov:skip=CKV_AWS_355:Official AWS Load Balancer Controller IAM policy (Describe* on *)
  # checkov:skip=CKV_AWS_290:Official AWS Load Balancer Controller IAM policy
  # checkov:skip=CKV_AWS_287:Official AWS Load Balancer Controller IAM policy
  name        = "${var.project}-${var.environment}-lb-controller"
  description = "AWS Load Balancer Controller (upstream iam_policy.json v2.14.1)"
  policy      = file("${path.module}/iam-policy-lbc.json")
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}
