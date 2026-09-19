# Trust model (SG-to-SG, not CIDRs except internet → ALB 80/443):
#   Internet → ALB SG :80/:443 → Node SG :8080 → RDS SG :3306
# RDS must never allow 0.0.0.0/0.

resource "aws_security_group" "eks_cluster" {
  # checkov:skip=CKV2_AWS_5:Attached by the EKS cluster in PETPLAT-12
  name        = "${local.name_prefix}-eks-cluster"
  description = "EKS cluster (control plane) security group"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster"
  })
}

resource "aws_security_group" "eks_node" {
  # checkov:skip=CKV2_AWS_5:Attached by the node group in PETPLAT-13
  name        = "${local.name_prefix}-eks-node"
  description = "EKS node security group"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-node"
  })
}

resource "aws_security_group" "rds" {
  # checkov:skip=CKV2_AWS_5:Attached by RDS in PETPLAT-22
  name        = "${local.name_prefix}-rds"
  description = "RDS MySQL from EKS nodes only"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds"
  })
}

resource "aws_security_group" "alb" {
  # checkov:skip=CKV2_AWS_5:Attached by the ingress ALB when LBC is installed
  name        = "${local.name_prefix}-alb"
  description = "Internet-facing ALB"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb"
  })
}

# --- Cluster ---

resource "aws_vpc_security_group_ingress_rule" "cluster_from_nodes_443" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "API server from nodes"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.eks_node.id
}

resource "aws_vpc_security_group_egress_rule" "cluster_all" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Cluster egress"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Nodes ---

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster_all" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "All from cluster SG"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_cluster.id
}

resource "aws_vpc_security_group_ingress_rule" "node_from_self" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Inter-node"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_node.id
}

resource "aws_vpc_security_group_ingress_rule" "node_kubelet_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Kubelet from cluster"
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  referenced_security_group_id = aws_security_group.eks_cluster.id
}

resource "aws_vpc_security_group_ingress_rule" "node_alb_8080" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "API Gateway from ALB (LBC IP targets)"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "node_all" {
  security_group_id = aws_security_group.eks_node.id
  description       = "Node egress"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- RDS ---

resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_nodes" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from EKS nodes"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.eks_node.id
}

# --- ALB ---

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  # checkov:skip=CKV_AWS_260:Internet-facing ALB HTTP (ADR-0001); TLS via ACM later
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nodes_8080" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To api-gateway pods (LBC target-type ip)"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.eks_node.id
}
