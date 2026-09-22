# External Secrets Operator IRSA (PETPLAT-37). kubectl install waits on E-3 apply.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "eso_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eso" {
  statement {
    sid    = "ReadPetclinicSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:petclinic/*",
    ]
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.project}-${var.environment}-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json

  tags = {
    Name = "${var.project}-${var.environment}-eso-role"
  }
}

resource "aws_iam_policy" "eso" {
  name        = "${var.project}-${var.environment}-eso"
  description = "ESO read of petclinic/* Secrets Manager secrets (ADR-0017)"
  policy      = data.aws_iam_policy_document.eso.json
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}
