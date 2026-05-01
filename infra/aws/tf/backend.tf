# -- infra/aw/tf/backend.tf 
# ============================================================================
# Terraform Backend Configuration
# ============================================================================

terraform {
  required_version = "~>1.14.0"

  cloud {

    organization = "subhamay-aws-projects"

    workspaces {
      name = "aws-csv-data-pipeline"
    }
  }
}