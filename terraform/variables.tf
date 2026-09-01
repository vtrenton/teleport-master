variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "teleport-gateway"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t2.micro"
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "vpc_id" {
  description = "ID of the existing VPC to deploy into"
  type        = string
}

variable "subnet_ids" {
  description = "IDs of existing subnets to deploy into, spanning at least 2 AZs (required by EKS for the control plane) - used for the cluster, node group, and Teleport proxy NLB"
  type        = list(string)
}

variable "node_tags" {
  description = "Additional tags applied to the EKS worker node EC2 instances, their EBS volumes, and the EKS cluster itself"
  type        = map(string)
  default     = {}
}

variable "dynamodb_backend_table_name" {
  description = "Name of the DynamoDB table used for Teleport cluster state (backend) storage"
  type        = string
}

variable "dynamodb_events_table_name" {
  description = "Name of the DynamoDB table used for Teleport cluster events storage"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket used for Teleport storage, accessible by worker nodes"
  type        = string
}

variable "home_ip" {
  description = "Home public IP address (no CIDR suffix) granted unrestricted access to worker nodes"
  type        = string
}

variable "node_key_name" {
  description = "Name for the AWS EC2 key pair used by worker nodes. Defaults to \"<cluster_name>-nodes-key\" if unset."
  type        = string
  default     = null
}
