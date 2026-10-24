output "db_address" {value = aws_db_instance.main.address}
output "db_secret_arn" {value = aws_secretsmanager_secret.db_url.arn}
output "openai_secret_arn" {value = aws_secretsmanager_secret.openai.arn}
output "vpc_id" {value = aws_vpc.main.id}
output "public_subnets" {value = aws_subnet.public[*].id}