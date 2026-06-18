variable "my_ip" {
  description = "Your public IP for SSH"
  type        = string
  default     = "0.0.0.0/0"
}

variable "project_name" {
  description = "Project name for resources"
  type        = string
  default     = "cicd-demo"
}
