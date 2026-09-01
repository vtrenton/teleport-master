data "aws_subnet" "nodes" {
  for_each = toset(var.subnet_ids)
  id       = each.value
}

resource "aws_security_group" "nodes" {
  name        = "${var.cluster_name}-node-sg"
  description = "EKS worker node SG - default deny, allow VPC-local TCP/UDP and unrestricted home IP access"
  vpc_id      = var.vpc_id

  ingress {
    description = "All TCP from the actual CIDR of each subnet in use"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [for s in data.aws_subnet.nodes : s.cidr_block]
  }

  ingress {
    description = "All UDP from the actual CIDR of each subnet in use"
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = [for s in data.aws_subnet.nodes : s.cidr_block]
  }

  ingress {
    description = "Unrestricted access from home IP"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.home_ip}/32"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-node-sg"
  }
}

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS control plane SG - explicit access to/from worker nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Nodes to control plane API"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]
  }

  egress {
    description     = "Control plane to node kubelet API"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]
  }

  egress {
    description     = "Control plane to node webhooks/extension API servers"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]
  }

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}
