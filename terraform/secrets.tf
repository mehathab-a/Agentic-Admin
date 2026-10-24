resource "aws_secretsmanager_secret" "db_url" {
    name_prefix = "agentic-admin/db-url-"
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id = aws_secretsmanager_secret.db_url.id
  secret_string = "postgresql://${var.db_username}:${random_password.db.result}@${aws_db_instance.main.address}:5432/${var.db_name}"
}

resource "aws_secretsmanager_secret" "openai" {
    name_prefix = "agentic-admin/openai-"
} 

