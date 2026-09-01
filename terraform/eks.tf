resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["${var.home_ip}/32"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
  ]

  tags = merge(
    { Name = var.cluster_name },
    var.node_tags
  )
}

resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-nodes-"
  key_name    = aws_key_pair.nodes.key_name

  network_interfaces {
    security_groups = [aws_security_group.nodes.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      { Name = "${var.cluster_name}-nodes" },
      var.node_tags
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags          = var.node_tags
  }

  tags = merge(
    { Name = "${var.cluster_name}-nodes" },
    var.node_tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.subnet_ids

  instance_types = [var.node_instance_type]

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
  ]

  tags = merge(
    { Name = "${var.cluster_name}-nodes" },
    var.node_tags
  )
}
