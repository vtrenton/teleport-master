terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }

  }
}

provider "aws" {
  region = var.region

  # Merged onto every taggable resource this provider creates. Resource-level
  # tags (e.g. Name) are kept alongside these; on a key collision the
  # resource-level value wins.
  default_tags {
    tags = var.resource_tags
  }
}
