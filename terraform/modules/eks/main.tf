locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = local.name_prefix
  node_policies = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

resource "aws_iam_role" "cluster" {
  name_prefix = "${local.name_prefix}-eks-cluster-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sts:AssumeRole",
        "sts:TagSession",
      ]
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_cloudwatch_log_group" "cluster" {
  # checkov:skip=CKV_AWS_158:AWS-managed CloudWatch encryption (ADR-0012)
  # checkov:skip=CKV_AWS_338:7-day retention by design (ADR-0013)
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-logs"
  })
}

resource "aws_eks_cluster" "this" {
  # checkov:skip=CKV_AWS_39:Public API restricted to operator /32 (ADR-0013)
  # checkov:skip=CKV_AWS_38:CIDR is var.api_allowed_cidrs from my_ip /32 at apply; module has no default so a module-only scan cannot see it (ADR-0013)
  # checkov:skip=CKV_AWS_37:api/audit/authenticator only; skip controllerManager and scheduler (ADR-0013)
  # checkov:skip=CKV_AWS_339:EKS 1.35 is STANDARD until 2027-03-27; Checkov catalog is stale
  # checkov:skip=CKV_AWS_58:AWS-managed secrets encryption; no customer CMK (ADR-0012)
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.api_allowed_cidrs
    security_group_ids      = [var.cluster_sg_id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]

  tags = merge(var.tags, {
    Name = local.cluster_name
  })
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list = ["sts.amazonaws.com"]
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-oidc"
  })
}

resource "aws_eks_access_entry" "deployer" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_iam_session_context.current.issuer_arn
  type          = "STANDARD"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-deployer"
  })
}

resource "aws_eks_access_policy_association" "deployer_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.deployer.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_iam_role" "node" {
  name_prefix = "${local.name_prefix}-eks-node-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-node"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.node_policies

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_launch_template" "nodes" {
  name_prefix = "${local.name_prefix}-eks-node-"
  description = "Managed node group launch template (IMDSv2 hop 1)"

  vpc_security_group_ids = [
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
    var.node_sg_id,
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-eks-node"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-eks-node"
    })
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-node-lt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Same security posture as the app template. Separate so the EC2 Name tag is
# petclinic-{env}-eks-observability in the console and Cost Explorer.
resource "aws_launch_template" "observability" {
  name_prefix = "${local.name_prefix}-eks-observability-"
  description = "Observability node group launch template (IMDSv2 hop 1)"

  vpc_security_group_ids = [
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
    var.node_sg_id,
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-eks-observability"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-eks-observability"
    })
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-observability-lt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  ami_type        = var.node_ami_type
  capacity_type   = "ON_DEMAND"
  instance_types  = var.node_instance_types
  version         = var.cluster_version

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  labels = {
    environment  = var.environment
    "managed-by" = "terraform"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nodes"
  })

  depends_on = [aws_iam_role_policy_attachment.node]
}

# Tainted pool shared by observability and ArgoCD (ADR-0021, ADR-0026).
# Own launch template so the instance Name is petclinic-{env}-eks-observability
# (IMDSv2 hop 1, encrypted gp3). Omitted unless either flag is true.
resource "aws_eks_node_group" "observability" {
  count = var.enable_observability || var.enable_argocd ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-observability"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  ami_type        = var.node_ami_type
  capacity_type   = "ON_DEMAND"
  instance_types  = var.observability_node_instance_types
  version         = var.cluster_version

  scaling_config {
    min_size     = 1
    max_size     = 1
    desired_size = 1
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.observability.id
    version = aws_launch_template.observability.latest_version
  }

  labels = {
    environment  = var.environment
    "managed-by" = "terraform"
    workload     = "observability"
  }

  taint {
    key    = "dedicated"
    value  = "observability"
    effect = "NO_SCHEDULE"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-observability"
  })

  depends_on = [aws_iam_role_policy_attachment.node]
}
