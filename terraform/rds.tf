# rds.tf
# A tiny Postgres instance for the agent app, plus the random password that
# gets wrapped into the DATABASE_URL secret (see secrets.tf).
#
# This is intentionally the cheapest safe-ish setup: single-AZ, 20 GiB, no
# Multi-AZ failover, no final snapshot on destroy. Great for dev, do NOT
# ship like this for prod.

# Random master password. 24 chars is well above RDS's 8-char minimum.
# special = false keeps the password alphanumeric so we don't have to worry
# about URL-encoding anything when we embed it in postgresql://user:pass@...
resource "random_password" "db" {
  length  = 24
  special = false
}

# Tells RDS which subnets it may place its ENI into. Needs >=2 AZs even
# when the instance itself is single-AZ (AWS requirement).
# name_prefix so re-creation doesn't collide on name.
resource "aws_db_subnet_group" "main" {
  name_prefix = "${var.project}-db-subnets-"
  description = "Subnets available to the ${var.project} RDS instance."
  subnet_ids  = aws_subnet.public[*].id

  tags = {
    Name = "${var.project}-db-subnets"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The database itself.
#   - db.t4g.micro + 20 GiB puts us very close to free tier.
#   - publicly_accessible = true gives it a resolvable public DNS name. The
#     actual security is enforced by the SG (operator IP + app SG only).
#   - skip_final_snapshot keeps `terraform destroy` quick and quiet. Flip to
#     false the moment this holds data you'd be sad to lose.
#   - apply_immediately skips the maintenance window — fine in dev, risky
#     in prod because some changes trigger a restart.
resource "aws_db_instance" "main" {
  identifier     = "${var.project}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage = 20

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = true
  skip_final_snapshot = true
  apply_immediately   = true

  tags = {
    Name = "${var.project}-db"
  }
}
