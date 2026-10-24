# ecs.tf
# Everything needed to actually run the app:
#   - ECS cluster (logical grouping, free)
#   - Task SG + the "app -> RDS" ingress rule
#   - Two IAM roles: execution (what AWS does on the task's behalf) and
#                    task (what the running code does itself)
#   - CloudWatch log group
#   - Task definition (the "recipe" for one copy of the app)
#   - ECS service (keeps N copies running, wires them into the ALB)
#
# Why Fargate? No EC2 to patch, 0.25 vCPU / 512 MiB is pennies per hour,
# and we don't need any of the EC2-only knobs (GPUs, host networking, etc.)

# The cluster. Just a namespace for the service — free on Fargate; you only
# pay for actual task runtime.
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"

  tags = {
    Name = "${var.project}-cluster"
  }
}

# SG stuck on each task's ENI. Only the ALB SG may hit the app port, so even
# though the task has a public IP, the public internet can't reach :8000
# directly — it has to go through the ALB.
resource "aws_security_group" "app" {
  name_prefix = "${var.project}-app-sg-"
  description = "SG for ECS tasks. Accepts 8000/tcp from the ALB only."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from the ALB SG"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Open egress because the task needs to reach:
  #   - ECR (image pull)
  #   - Secrets Manager (secret injection at launch)
  #   - CloudWatch Logs (shipping stdout/stderr)
  #   - OpenAI / LangSmith (app traffic)
  #   - RDS (via the SG rule below)
  egress {
    description = "Allow all outbound (ECR, Secrets Manager, OpenAI, RDS)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-app-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_secretsmanager_secret" "openai" {
  name = var.openai_secret_name
}

data "aws_secretsmanager_secret" "langsmith" {
  name = var.langsmith_secret_name
}

# Standalone rule so we don't create a cycle between the RDS SG and the app
# SG. Lives here (not in security.tf) because it needs app SG to exist first.
resource "aws_security_group_rule" "rds_from_app" {
  description              = "Allow ECS app tasks to reach RDS on 5432"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id # rule attached to RDS SG
  source_security_group_id = aws_security_group.app.id # traffic allowed FROM app SG
}

# ---------------------------------------------------------------------------
# IAM — execution role
# ---------------------------------------------------------------------------
# This is NOT what the application runs as. It's what the ECS agent uses on
# behalf of the task to:
#   - pull the container image from ECR
#   - resolve secretsmanager:// references and inject env vars
#   - push logs to CloudWatch
# Keep its permissions tight — it has the keys to your secrets.

# Trust policy — any ECS task can assume this role (standard pattern).
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name_prefix        = "${var.project}-ecs-exec-"
  description        = "ECS task execution role for ${var.project} (pull image, read secrets, write logs)."
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# AWS-managed baseline: ECR + CloudWatch Logs. Don't try to replace this with
# a hand-written policy unless you really know what you're doing — the
# managed one tracks new permissions as ECS evolves.
resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The specific permission the task launch needs: read our three secrets.
# Scoped by ARN so it can't read anything else in the account.
resource "aws_iam_role_policy" "execution_secrets" {
  name = "${var.project}-exec-secrets"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.db_url.arn,
        data.aws_secretsmanager_secret.openai.arn,
        data.aws_secretsmanager_secret.langsmith.arn,
      ]
    }]
  })
}

# ---------------------------------------------------------------------------
# IAM — task role
# ---------------------------------------------------------------------------
# This IS what the application process runs as. Currently empty because the
# only AWS thing the app needs is secrets, and those are injected by the
# execution role before the process even starts.
#
# When we add Bedrock / S3 / etc. calls, attach the policies here (NOT to
# the execution role).
resource "aws_iam_role" "task" {
  name_prefix        = "${var.project}-ecs-task-"
  description        = "App-level role used by the running ${var.project} container."
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# Where container stdout/stderr goes. 7 days is cheap and plenty for
# debugging a dev stack. Crank this up (30-90) once there's real traffic
# and you want postmortems.
resource "aws_cloudwatch_log_group" "app" {
  name_prefix       = "/ecs/${var.project}-"
  retention_in_days = 7

  tags = {
    Name = "${var.project}-app-logs"
  }
}

# ---------------------------------------------------------------------------
# Task definition — the blueprint for one running copy of the app.
# ---------------------------------------------------------------------------
#   cpu/memory are STRINGS (yes, really) and must be a valid Fargate combo:
#   https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-defs.html
#   "256" vCPU units = 0.25 vCPU, "512" MiB = cheapest valid combo.
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # required for Fargate
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  # Single container. If you add a sidecar (e.g. a telemetry agent), it goes
  # as another object in this list.
  container_definitions = jsonencode([{
    name  = "${var.project}-app"
    image = var.ecr_image

    portMappings = [{ containerPort = 8000 }]

    # Plain env vars (safe to put in state — nothing secret here).
    environment = [
      { name = "LLM_PROVIDER", value = "openai" },
      { name = "OPENAI_MODEL", value = "gpt-5-mini" },
      { name = "LANGSMITH_TRACING", value = "true" },
      { name = "LANGSMITH_PROJECT", value = "${var.project}-prod" },
      { name = "AWS_REGION", value = var.region },
    ]

    # Secret env vars — ECS resolves the ARN at launch and injects the
    # plaintext value. The task never sees the ARN, the app just sees
    # DATABASE_URL=postgres://... in its env.
    secrets = [
      { name = "DATABASE_URL", valueFrom = aws_secretsmanager_secret.db_url.arn },
      { name = "OPENAI_API_KEY", valueFrom = data.aws_secretsmanager_secret.openai.arn },
      { name = "LANGSMITH_API_KEY", valueFrom = data.aws_secretsmanager_secret.langsmith.arn },
    ]

    # stdout/stderr -> CloudWatch. Streams are prefixed with the project
    # name so multiple apps in the same group stay readable.
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "${var.project}-app"
      }
    }
  }])

  tags = {
    Name = "${var.project}-app-taskdef"
  }
}

# ---------------------------------------------------------------------------
# ECS Service — keeps `desired_count` copies running and registers them
# with the ALB target group.
# ---------------------------------------------------------------------------
# Scaling: bump `desired_count` or add an aws_appautoscaling_target later.
# Rolling deploys happen automatically on task_definition changes (ECS
# default deployment config: 100% min, 200% max, draining old tasks when
# new ones pass health checks).
resource "aws_ecs_service" "app" {
  name            = "${var.project}-app-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true # mandatory without a NAT gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "${var.project}-app" # must match container_definitions.name above
    container_port   = 8000
  }

  # Don't try to register targets before the listener (and therefore the TG
  # wiring on the ALB) actually exists. Without this, the first apply
  # occasionally fails with a "target group not associated" error.
  depends_on = [aws_lb_listener.http]

  tags = {
    Name = "${var.project}-app-svc"
  }
}
