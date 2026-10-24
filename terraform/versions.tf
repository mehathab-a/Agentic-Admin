# versions.tf
# Boring but important: what Terraform version is allowed to touch this stack,
# which providers get pulled in, and the default AWS provider wiring.
#
# If you ever bump the AWS provider major (5.x -> 6.x), expect to re-read the
# upgrade guide — a handful of resource schemas usually change.

terraform {
  # Anything older than 1.6 misses `moved` blocks and a few validation niceties
  # we rely on. 1.17.x (what you have locally) is fine.
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # ~> 5.0 means: any 5.x is fine, but don't auto-jump to 6.x on us.
      version = "~> 5.0"
    }

    # Only used to generate the RDS master password. Could be swapped for
    # `aws_secretsmanager_random_password` later if we want AWS to own the
    # entropy, but keeping it client-side is simpler for now.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# The default AWS provider. Every resource below picks this up unless it
# explicitly says `provider = aws.something_else` (we never do).
provider "aws" {
  region = var.region

  # Pulls creds from ~/.aws/credentials -> [agent] profile. If you ever see
  # "NoCredentialProviders", that profile is probably missing or expired.
  profile = "agent"

  # These tags get stamped on every taggable resource automatically. Super
  # useful when you want to find/clean up everything this stack created, or
  # split the bill by project in Cost Explorer.
  default_tags {
    tags = {
      project = "agentic-admin"
      managed = "terraform"
    }
  }
}
