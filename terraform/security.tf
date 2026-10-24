# security.tf
# Just the RDS security group. The ALB SG lives in alb.tf and the ECS task SG
# lives in ecs.tf. The "app -> RDS" ingress rule also lives in ecs.tf as a
# standalone `aws_security_group_rule` — if we put it inline on the RDS SG
# here, we'd have a circular dependency (RDS SG references app SG, app SG
# would already need RDS SG to exist). The separate rule breaks the cycle.
#
# IMPORTANT: AWS SG descriptions have a weirdly narrow allowed charset.
# No apostrophes, quotes, question marks, %, etc. Keep them boring ASCII
# with just . , _ - / () etc. (This is what tripped the first apply.)

resource "aws_security_group" "rds" {
  # name_prefix (not name) so Terraform can roll a new SG and swap resources
  # over without a name collision. AWS tacks on an 8-char random suffix.
  name_prefix = "${var.project}-rds-sg-"
  description = "Postgres (5432) in from operator IP and ECS tasks. Egress all."
  vpc_id      = aws_vpc.main.id

  # Only your laptop IP can reach psql from the outside world. Everything else
  # on the open internet gets rejected at the SG layer, even though the RDS
  # instance is technically publicly reachable.
  ingress {
    description = "Postgres from operator laptop (var.my_ip)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  # Standard "all outbound" — matches AWS's default and keeps RDS features
  # like Enhanced Monitoring happy if we ever turn them on.
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-rds-sg"
  }

  # name_prefix forces replacement when the SG changes. Build the new one
  # first so RDS doesn't briefly have no SG attached (which AWS won't allow).
  lifecycle {
    create_before_destroy = true
  }
}
