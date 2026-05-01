# -- infra/platform/tf/terraform.tfvars (Platform Module)
# ============================================================================
# Terraform Variable Values
# ============================================================================

s3_buckets_config_path       = "config/aws/devl/config.json"

# ----------------------------------------------------------------------------
# Project Configuration
# AWS(AWS) - Snowflake (SF) - End to End (E2E)
# ----------------------------------------------------------------------------
project_code        = "cust360"
cost_center         = "0709"
environment         = "devl"
data_classification = "confidential"
component           = "platform"
owner               = "Subhamay Bhattacharyya"
