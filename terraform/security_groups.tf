resource "aws_security_group" "nodes" {
  name        = "${var.cluster_name}-node-sg"
  description = "EKS worker node SG - default deny, allow VPC-local TCP/UDP and unrestricted home IP access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All TCP within the VPC CIDR"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "All UDP within the VPC CIDR"
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = [aws_vpc.main.cidr_block]
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
