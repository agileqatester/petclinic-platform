locals {
  name_prefix = "${var.project}-${var.environment}"
}

data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_eip" "this" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-eip"
  })
}

resource "aws_security_group" "this" {
  name_prefix = "${local.name_prefix}-nat-"
  description = "NAT instance (VPC traffic in, no SSH)"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_clients" {
  count = length(var.client_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "Traffic from client SG to be NATed (no SSH)"
  ip_protocol                  = "-1"
  referenced_security_group_id = var.client_security_group_ids[count.index]
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "NAT egress to the internet"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_iam_role" "ssm" {
  count = var.enable_ssm ? 1 : 0

  name_prefix = "${local.name_prefix}-nat-ssm-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-ssm"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.enable_ssm ? 1 : 0

  role       = aws_iam_role.ssm[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  count = var.enable_ssm ? 1 : 0

  name_prefix = "${local.name_prefix}-nat-ssm-"
  role        = aws_iam_role.ssm[0].name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "this" {
  # checkov:skip=CKV_AWS_88:NAT instance must have a public IP and EIP (ADR-0001)
  ami           = var.ami_id != "" ? var.ami_id : data.aws_ami.al2023_arm.id
  instance_type = var.instance_type
  subnet_id     = var.public_subnet_ids[0]

  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.this.id]
  source_dest_check           = false
  iam_instance_profile        = var.enable_ssm ? aws_iam_instance_profile.ssm[0].name : null

  # Instance profile must exist and be attached before launch (AWS eventual consistency).
  depends_on = [aws_iam_role_policy_attachment.ssm]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = 8
  }

  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-nat.conf
    sysctl -p /etc/sysctl.d/99-nat.conf
    dnf install -y iptables-nft amazon-ssm-agent
    IFACE=$(ip -o -4 route show default | awk '{print $5}')
    iptables -P FORWARD DROP
    iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -s ${var.vpc_cidr} -o "$IFACE" -m conntrack --ctstate NEW -j ACCEPT
    iptables -t nat -A POSTROUTING -s ${var.vpc_cidr} -o "$IFACE" -j MASQUERADE
    mkdir -p /etc/sysconfig
    iptables-save > /etc/sysconfig/iptables
    IPT_RESTORE="$(command -v iptables-restore)"
    cat > /etc/systemd/system/petclinic-nat-iptables.service << UNIT
    [Unit]
    Description=Restore NAT iptables rules
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=$${IPT_RESTORE} /etc/sysconfig/iptables

    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable --now petclinic-nat-iptables.service
    systemctl enable --now amazon-ssm-agent
  EOF

  lifecycle {
    ignore_changes = [
      ami,
      credit_specification,
    ]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat"
    Role = "nat"
  })
}

resource "aws_eip_association" "this" {
  instance_id   = aws_instance.this.id
  allocation_id = aws_eip.this.id
}
