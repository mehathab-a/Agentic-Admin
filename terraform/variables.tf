# variables.tf
# Inputs you can tweak without editing resources. Anything without a `default`
# is required — Terraform will prompt for it (or error in CI) if you forget.
#
# Easiest way to supply the required ones: a `terraform.tfvars` file next to
# this one. It's gitignored, so your IP won't leak.

variable "region" {
  description = "AWS region for the whole stack. If you change this, remember the ECR image has to exist in the same region."
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Logical database name created inside the Postgres instance."
  type        = string
  default     = "agent"
}

variable "db_username" {
  description = "Master username for Postgres. Password is generated, not set here."
  type        = string
  default     = "agent_app"
}

# Your public IPv4 address, no CIDR suffix. The /32 gets appended in the SG.
# Grab it with:  curl -s https://checkip.amazonaws.com
# If your home ISP rotates IPs, re-apply after reconnecting.
variable "my_ip" {
  description = "Public IPv4 of the operator machine. Used to whitelist psql into RDS."
  type        = string
}

# Full image reference the ECS task should run. Use a tag during active dev,
# switch to an immutable @sha256 digest once the image stops moving so ECS
# can tell when it really changed.
variable "ecr_image" {
  description = "Full ECR image URI for the app container, e.g. 123.dkr.ecr.us-east-1.amazonaws.com/agentic-admin:latest"
  type        = string
}

# One place to rename the whole stack. Changing this will rename a *lot* of
# resources on the next apply (basically a destroy + recreate for the ones
# that use `name` instead of `name_prefix`), so don't flip it casually.
variable "project" {
  description = "Short project slug used in resource names and name_prefixes."
  type        = string
  default     = "agentic-admin"
}

variable "openai_secret_name" {
  description = "Name of the OpenAI API key secret in Secrets Manager."
  type    = string
  default = "agentic-admin/openai_api_key"
}

variable "langsmith_secret_name" {
  description = "Name of the LangSmith API key secret in Secrets Manager."
  type    = string
  default = "agentic-admin/langsmith_api_key"
}