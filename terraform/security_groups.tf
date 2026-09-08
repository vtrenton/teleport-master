resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS control plane SG - explicit access to/from worker nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Nodes to control plane API"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  egress {
    description     = "Control plane to node kubelet API"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  egress {
    description     = "Control plane to node webhooks/extension API servers"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}
