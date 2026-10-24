resource "aws_security_group" "rds" {
    name_prefix = "rds-"
    vpc_id = aws_vpc.main.id

    # laptop access for psql and ingestion
    ingress {
        from_port = 5432
        to_port = 5432
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # ECS tasks (added in 4d via the app SG)
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}