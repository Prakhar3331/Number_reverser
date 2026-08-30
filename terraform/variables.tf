variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "number-reverser"
}

variable "node_instance_type" {
  description = "EC2 Instance type for EKS worker node (t3.micro or t2.micro for AWS Free Tier)"
  type        = string
  default     = "t3.micro"
}
