locals {

}

variable "app_name" {
  type        = string
  description = "App name (SP)"
}

variable "github_org" {
  type        = string
  description = "GitHub Organization"
}

variable "github_repository" {
  type        = string
  description = "GitHub Repository"
}

variable "subscription_id" {
  type        = string
  description = "Suscription ID"
}

variable "github_environment_name" {
  type        = string
  description = "Environemnt name created into github, associated to this account sp"
}

variable "container_app_github_runner_env_rg" {
  type        = string
  description = "Resource group where the container app environment is located"
}
