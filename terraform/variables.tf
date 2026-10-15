variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-auto-demo"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.37"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "eks-auto-mode-demo"
    ManagedBy   = "terraform"
  }
}
