variable "region"      { default = "us-east-1" }
variable "db_name"     { default = "agent" }
variable "db_username" { default = "agent_app" }
variable "my_ip"       { type = string }  # your IP for RDS access