#
# ECS task for migrations
#

resource "aws_cloudwatch_log_group" "pipelineci_migrations_log_group" {
  name              = "/ecs/pipelineci-backend-migrations"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "pipelineci_migrations_task_definition" {
  family                    = "pipelineci-migrations-task"
  network_mode              = "awsvpc"
  requires_compatibilities  = ["FARGATE"]
  execution_role_arn        = aws_iam_role.ecs_execution_role.arn
  cpu                       = "256"
  memory                    = "512"

  container_definitions = jsonencode([
    {
      name  = "pipelineci-migrations",
      image = "888577039580.dkr.ecr.us-west-2.amazonaws.com/pipelineci-backend:0.1",
      command = ["npm", "run", "migrate:prod"],
      portMappings = [
        {
          containerPort = 3000,
          hostPort      = 3000,
        },
      ],
      environment = [
        {
          "name": "AUTH0_AUDIENCE",
          "value": var.AUTH0_AUDIENCE
        },
        {
          "name": "AUTH0_ISSUER_BASE_URL",
          "value": var.AUTH0_ISSUER_BASE_URL
        },
        {
          "name": "NODE_ENV",
          "value": var.NODE_ENV
        },
        {
          "name": "ORGANIZATIONS_TABLE_NAME",
          "value": var.ORGANIZATIONS_TABLE_NAME
        },
        {
          "name": "GITHUB_APP_IDENTIFIER",
          "value": var.GITHUB_APP_IDENTIFIER
        },
        {
          "name": "GITHUB_APP_PRIVATE_KEY",
          "value": var.GITHUB_APP_PRIVATE_KEY
        },
        {
          "name": "DB_HOST",
          "value": aws_db_instance.pipelineci_db.address
        },
        {
          "name": "DB_USER",
          "value": aws_db_instance.pipelineci_db.username
        },
        {
          "name": "DB_PASSWORD",
          "value": var.DB_PASSWORD
        },
        {
          "name": "DB_NAME",
          "value": aws_db_instance.pipelineci_db.db_name
        },
        {
          "name": "DB_PORT",
          "value": tostring(aws_db_instance.pipelineci_db.port)
        },
        {
          "name": "RDS_CERT_BUNDLE",
          "value": var.RDS_CERT_BUNDLE
        }
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.pipelineci_migrations_log_group.name
          awslogs-region        = "us-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    },
  ])
}

resource "aws_security_group" "pipelineci_ecs_migrations_sg" {
  name        = "pipelineci-ecs-migrations-sg"
  description = "Security group for Migrations"

  vpc_id = aws_vpc.pipelineci_vpc.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    security_groups = [aws_security_group.pipelineci_lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "pipelineci_ecs_migrations_sg" {
  value       = aws_security_group.pipelineci_ecs_migrations_sg.id
  description = "Migrations security group id"
}