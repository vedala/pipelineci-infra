#
# ECS
#

resource "aws_cloudwatch_log_group" "pipelineci_ghapp_log_group" {
  name              = "/ecs/pipelineci-app"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "pipelineci_ghapp_task_definition" {
  family                    = "pipelineci-gh-app-task"
  network_mode              = "awsvpc"
  requires_compatibilities  = ["FARGATE"]
  execution_role_arn        = aws_iam_role.ecs_execution_role.arn
  cpu                       = "256"
  memory                    = "512"

  container_definitions = jsonencode([
    {
      name  = "pipelineci-ghapp-container",
      image = "888577039580.dkr.ecr.us-west-2.amazonaws.com/pipelineci-gh-app:latest",
      portMappings = [
        {
          containerPort = 4000,
          hostPort      = 4000,
        },
      ],
      environment = [
        {
          "name": "NODE_ENV",
          "value": var.NODE_ENV
        },
        {
          "name": "GITHUB_APP_IDENTIFIER",
          "value": var.GITHUB_APP_IDENTIFIER
        },
        {
          "name": "WEBHOOK_SECRET",
          "value": var.WEBHOOK_SECRET
        },
        {
          "name": "GITHUB_APP_PRIVATE_KEY",
          "value": var.GITHUB_APP_PRIVATE_KEY
        },
        {
          "name": "PORT",
          "value": var.GITHUB_APP_PORT
        },
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.pipelineci_ghapp_log_group.name
          awslogs-region        = "us-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    },
  ])
}

resource "aws_ecs_service" "pipelineci_ghapp_service" {
  name            = "pipelineci-ghapp-service"
  cluster         = aws_ecs_cluster.pipelineci_cluster.id
  task_definition = aws_ecs_task_definition.pipelineci_ghapp_task_definition.arn
  desired_count   = 2

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets           = [aws_subnet.pipelineci_private_subnet_01.id, aws_subnet.pipelineci_private_subnet_02.id]
    security_groups   = [aws_security_group.pipelineci_ghapp_ecs_service_sg.id]
    assign_public_ip  = false
  }

  load_balancer {
    target_group_arn  = aws_lb_target_group.pipelineci_ghapp_target_group.arn
    container_name    = "pipelineci-ghapp-container"
    container_port    = 4000
  }

  depends_on = [
    aws_ecs_task_definition.pipelineci_ghapp_task_definition,
    aws_lb_target_group.pipelineci_ghapp_target_group
  ]
}

resource "aws_security_group" "pipelineci_ghapp_ecs_service_sg" {
  name        = "pipelineci-ghapp-ecs-service-sg"
  description = "Security group for Github App ECS service"

  vpc_id = aws_vpc.pipelineci_vpc.id

  ingress {
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    security_groups = [aws_security_group.pipelineci_ghapp_lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
}
