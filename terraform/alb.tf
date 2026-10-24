# alb.tf
# Public Application Load Balancer in front of the ECS service.
#
# Flow:
#   internet -> ALB (:80) -> listener -> target group -> ECS task ENI (:8000)
#
# What's here:
#   - aws_security_group.alb     : what the ALB itself is allowed to talk to
#   - aws_lb.main                : the ALB resource (public, HTTP)
#   - aws_lb_target_group.app    : where tasks register themselves
#   - aws_lb_listener.http       : :80 -> target group
#
# NOT here (yet): HTTPS, ACM cert, 443 listener, HTTP->HTTPS redirect.
# Add those before putting this in front of anything real.

# SG for the load balancer. Public HTTP in, anything out (needed so the ALB
# can reach the task ENIs on 8000). SG descriptions can be plenty long —
# only the character set is restricted — so project-prefixed names are fine.
resource "aws_security_group" "alb" {
  name_prefix = "${var.project}-alb-sg-"
  description = "Allows public HTTP (80) in; all out to ECS tasks."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the public internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound (to ECS task ENIs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The ALB itself. Two subnets in two AZs = AWS is happy.
# We use `name` instead of `name_prefix` because the LB name_prefix limit is
# a brutal 6 chars, and having a stable, readable name is worth more here
# than easy churn.
resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]

  tags = {
    Name = "${var.project}-alb"
  }
}

# Target group the Fargate tasks register into.
#   - target_type = "ip" is required for awsvpc (Fargate) tasks.
#   - Health check hits GET /healthz on the container port.
#
# ⚠️ aws_lb_target_group `name_prefix` caps at 6 chars (AWS limit, not TF).
# "aa-tg-" is exactly 6. Anything longer errors out at plan/apply.
resource "aws_lb_target_group" "app" {
  name_prefix = "aa-tg-"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/healthz"
    healthy_threshold   = 2  # two consecutive 2xx and the target is in service
    unhealthy_threshold = 3  # three failures in a row and it gets drained
    timeout             = 5  # seconds per probe
    interval            = 30 # seconds between probes
  }

  tags = {
    Name = "${var.project}-app-tg"
  }

  # The listener below references this TG, so we need to be able to swap it
  # out without a brief period where no TG exists.
  lifecycle {
    create_before_destroy = true
  }
}

# Port 80 listener. Everything in, forwarded straight to the TG. If you add
# HTTPS later, convert this to a 301 redirect to 443 and add a new 443
# listener with the ACM cert.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
