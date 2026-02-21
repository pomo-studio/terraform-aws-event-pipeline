# Terraform Cloud workspace for event-pipeline module
# Uses the reusable workspace module from pomo-studio

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.50"
    }
  }
}

# Configure TFE provider (uses TFE_TOKEN env var)
provider "tfe" {
  organization = var.tfc_organization
}

# Create the workspace
resource "tfe_workspace" "this" {
  name         = var.workspace_name
  organization = var.tfc_organization
  description  = "Event Pipeline module - validation and testing"

  # VCS-driven
  vcs_repo {
    identifier     = "pomo-studio/terraform-aws-event-pipeline"
    oauth_token_id = var.oauth_token_id
  }

  # Auto-apply for module development
  auto_apply = true

  # Terraform version
  terraform_version = "~> 1.7.0"

  # Working directory for examples
  working_directory = "examples/complete"

  tags = ["module", "event-pipeline", "aws"]
}

# Variables
variable "tfc_organization" {
  type    = string
  default = "Pitangaville"
}

variable "workspace_name" {
  type    = string
  default = "event-pipeline"
}

variable "oauth_token_id" {
  type        = string
  description = "Terraform Cloud OAuth token ID for GitHub integration"
}

output "workspace_id" {
  value = tfe_workspace.this.id
}

output "workspace_url" {
  value = "https://app.terraform.io/app/${var.tfc_organization}/workspaces/${var.workspace_name}"
}
