# Variables for our Terraform configuration


variable "project_git_url" {
  description = "Git repository URL for the project"
  type        = string
  default     = "git@github.com:Ling-Ling23/minikube_apps_infra_app_one.git"
}

variable "project_dir" {
  description = "Project directory inside the container"
  type        = string
  default     = "/app/src"
}

variable "app_replicas" {
  description = "Number of replicas for the application"
  type        = number
  default     = 2
}