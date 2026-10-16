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

variable "endpoint_public_access" {
  description = "Expose the EKS API endpoint publicly. Default false: the API is private and reached through scripts/tunnel.sh (SSM port-forward)."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint, only used when endpoint_public_access = true. Use your own /32, never 0.0.0.0/0."
  type        = list(string)
  default     = []
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
