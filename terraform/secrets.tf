# secrets.tf
# Three Secrets Manager entries the running task reads at startup:
#   - db_url    : full postgresql:// connection string (Terraform fills this)
#   - openai    : OpenAI API key          (you fill this in by hand, see below)
#   - langsmith : LangSmith API key       (same deal)
#
# The ECS execution role in ecs.tf has GetSecretValue on all three, which is
# how the container ends up with DATABASE_URL / OPENAI_API_KEY / etc. in its
# environment at launch.
#
# Why name_prefix instead of name?
#   Secrets Manager has a 7-day "scheduled for deletion" window. If you ever
#   destroy and immediately re-apply with the same `name`, AWS says "that
#   name is still reserved". name_prefix sidesteps that permanently.

# The database URL. We stitch it together from the RDS address + the random
# password we generated in rds.tf. No URL-encoding needed since the password
# is alphanumeric (special = false on random_password).
resource "aws_secretsmanager_secret" "db_url" {
  name_prefix = "${var.project}/db-url-"
  description = "Postgres connection URL for the ${var.project} app."
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id     = aws_secretsmanager_secret.db_url.id
  secret_string = "postgresql://${var.db_username}:${random_password.db.result}@${aws_db_instance.main.address}:5432/${var.db_name}"
}

# OpenAI API key. Terraform just creates the empty secret shell. Fill the
# actual value yourself after apply, e.g.:
#   aws secretsmanager put-secret-value --profile agent \
#     --secret-id "$(terraform output -raw openai_secret_arn)" \
#     --secret-string "sk-..."
# If the task was already running when you set this, force a redeploy so
# new tasks pick up the value:
#   aws ecs update-service --cluster <cluster> --service <svc> \
#     --force-new-deployment --profile agent
resource "aws_secretsmanager_secret" "openai" {
  name = "${var.project}/openai_api_key"
  description = "OpenAI API key used by the ${var.project} app."
}

# Same story as OpenAI — created empty, you populate it manually.
resource "aws_secretsmanager_secret" "langsmith" {
  name = "${var.project}/langsmith_api_key"
  description = "LangSmith API key used by the ${var.project} app."
}
