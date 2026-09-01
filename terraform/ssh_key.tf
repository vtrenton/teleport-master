resource "tls_private_key" "nodes" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "nodes" {
  key_name   = coalesce(var.node_key_name, "${var.cluster_name}-nodes-key")
  public_key = tls_private_key.nodes.public_key_openssh
}

resource "local_sensitive_file" "nodes_private_key" {
  content         = tls_private_key.nodes.private_key_openssh
  filename        = "${path.module}/out/${var.cluster_name}-nodes.pem"
  file_permission = "0600"
}
