resource "random_password" "db" {
    length = 24
    special = false
}

resource "aws_db_subnet_group" "main" {
    name = "agentic-admin"
    subnet_ids = aws_subnet.public[*].id
}

resource "aws_db_instance" "main" {
    identifier = "agentic-admin"
    engine = "postgres"
    engine_version = "16"
    instance_class = "db.t4g.micro"
    allocated_storage = 20
    db_name = var.db_name
    username = var.db_username
    password = random_password.db.result
    db_subnet_group_name = aws_db_subnet_group.main.name
    vpc_security_group_ids = [aws_security_group.rds.id]
    publicly_accessible = true
    skip_final_snapshot = true
    apply_immediately = true
}