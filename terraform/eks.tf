locals {
  # compact() drops office_ip when it's unset.
  admin_cidrs = [for ip in compact([var.home_ip, var.office_ip]) : "${ip}/32"]
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = local.admin_cidrs
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
  ]

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-nodes-"
  key_name    = aws_key_pair.nodes.key_name

  network_interfaces {
    security_groups = [var.node_security_group_id]
  }

  # Instances, volumes, and ENIs are launched by the node group's ASG, not by
  # Terraform, so provider default_tags never reach them - tag them here.
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      { Name = "${var.cluster_name}-nodes" },
      var.resource_tags
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      { Name = "${var.cluster_name}-nodes" },
      var.resource_tags
    )
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = merge(
      { Name = "${var.cluster_name}-nodes" },
      var.resource_tags
    )
  }

  tags = {
    Name = "${var.cluster_name}-nodes"
  }

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

  tags = {
    Name = "${var.cluster_name}-nodes"
  }
}

# EKS creates these two itself, outside Terraform, so provider default_tags
# never reach them - tag them explicitly.

resource "aws_ec2_tag" "cluster_sg" {
  for_each = var.resource_tags

  resource_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  key         = each.key
  value       = each.value
}

resource "aws_autoscaling_group_tag" "nodes" {
  for_each = var.resource_tags

  autoscaling_group_name = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name

  tag {
    key   = each.key
    value = each.value
    # Instances already get these from the launch template's tag_specifications.
    propagate_at_launch = false
  }
}
