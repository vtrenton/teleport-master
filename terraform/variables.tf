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
  default     = "t3.large"
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

variable "public_subnet_ids" {
  description = "IDs of existing public subnets (where the Teleport proxy NLB will be provisioned)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "IDs of existing private subnets (where worker nodes run)"
  type        = list(string)
}

variable "node_tags" {
  description = "Additional tags applied to the EKS worker node EC2 instances and their EBS volumes"
  type        = map(string)
  default     = {}
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for Teleport cluster state/events storage"
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
