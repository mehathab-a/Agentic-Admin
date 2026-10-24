# outputs.tf
# Things terraform prints after apply, and that you can grab from scripts with
# `terraform output -raw <name>`. Keep these minimal — anything sensitive
# (the actual DB password, the actual secret values) should NOT be an output.

output "vpc_id" {
  description = "VPC that holds the whole stack."
  value       = aws_vpc.main.id
}

output "public_subnets" {
  description = "IDs of the two public subnets (one per AZ)."
  value       = aws_subnet.public[*].id
}

output "db_address" {
  description = "RDS Postgres endpoint hostname (no port)."
  value       = aws_db_instance.main.address
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for the postgresql:// connection URL."
  value       = aws_secretsmanager_secret.db_url.arn
}

output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key (value filled in by hand)."
  value       = data.aws_secretsmanager_secret.openai.arn
}

output "langsmith_secret_arn" {
  description = "Secrets Manager ARN for the LangSmith API key (value filled in by hand)."
  value       = data.aws_secretsmanager_secret.langsmith.arn
}

output "alb_url" {
  description = "Public URL of the app (HTTP, port 80)."
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecs_cluster_name" {
  description = "ECS cluster name — handy for aws ecs update-service calls."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name — handy for aws ecs update-service calls."
  value       = aws_ecs_service.app.name
}

output "log_group_name" {
  description = "CloudWatch Logs group receiving container stdout/stderr."
  value       = aws_cloudwatch_log_group.app.name
}
