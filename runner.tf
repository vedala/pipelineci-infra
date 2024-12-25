#
# Pipelineci Runner
#

#
# ECS for Runner
#

resource "aws_cloudwatch_log_group" "pipelineci_runner_log_group" {
  name              = "/ecs/pipelineci-runner"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "pipelineci_runner_task_definition" {
  family                    = "pipelineci-runner-task"
  network_mode              = "awsvpc"
  requires_compatibilities  = ["FARGATE"]
  execution_role_arn        = aws_iam_role.ecs_execution_role.arn
  cpu                       = "256"
  memory                    = "512"

  container_definitions = jsonencode([
    {
      name  = "pipelineci-runner-container",
      image = "888577039580.dkr.ecr.us-west-2.amazonaws.com/pipelineci-runner:latest",
      command = ["npm", "start"],
      portMappings = [
        {
          containerPort = 4000,
          hostPort      = 4000,
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
        },
        {
          "name": "WEBHOOK_SECRET",
          "value": var.WEBHOOK_SECRET
        },
        {
          "name": "PORT",
          "value": var.RUNNER_PORT
        },
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.pipelineci_runner_log_group.name
          awslogs-region        = "us-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    },
  ])
}

resource "aws_ecs_service" "pipelineci_runner_service" {
  name            = "pipelineci-runner-service"
  cluster         = aws_ecs_cluster.pipelineci_cluster.id
  task_definition = aws_ecs_task_definition.pipelineci_runner_task_definition.arn
  desired_count   = 2

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets           = [aws_subnet.pipelineci_private_subnet_01.id, aws_subnet.pipelineci_private_subnet_02.id]
    security_groups   = [aws_security_group.pipelineci_ecs_runner_sg.id]
    assign_public_ip  = false
  }

  load_balancer {
    target_group_arn  = aws_lb_target_group.pipelineci_runner_target_group.arn
    container_name    = "pipelineci-runner-container"
    container_port    = 4000
  }

  depends_on = [
    aws_ecs_task_definition.pipelineci_runner_task_definition,
    aws_lb_target_group.pipelineci_runner_target_group
  ]
}

# resource "aws_security_group" "pipelineci_runner_ecs_service_sg" {
#   name        = "pipelineci-runner-ecs-service-sg"
#   description = "Security group for Github App ECS service"

#   vpc_id = aws_vpc.pipelineci_vpc.id

#   ingress {
#     from_port   = 4000
#     to_port     = 4000
#     protocol    = "tcp"
#     security_groups = [aws_security_group.pipelineci_runner_lb_sg.id]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"  # Allow all outbound traffic
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

resource "aws_security_group" "pipelineci_ecs_runner_sg" {
  name        = "pipelineci-ecs-runner-sg"
  description = "Security group for Runner"

  vpc_id = aws_vpc.pipelineci_vpc.id

  ingress {
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    security_groups = [aws_security_group.pipelineci_runner_lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#
# Load Balancer, Runner
#

resource "aws_lb" "pipelineci_runner_alb" {
  name                = "pipelineci-runner-alb"
  internal            = false
  load_balancer_type  = "application"
  subnets             = [aws_subnet.pipelineci_public_subnet_01.id, aws_subnet.pipelineci_public_subnet_02.id]
  security_groups     = [aws_security_group.pipelineci_runner_lb_sg.id]
}

resource "aws_lb_target_group" "pipelineci_runner_target_group" {
  name        = "pipelineci-runner-target-group"
  port        = 4000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.pipelineci_vpc.id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = 4000
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-499"
  }
}

resource "aws_lb_listener" "pipelineci_runner_lb_listener" {
  load_balancer_arn = aws_lb.pipelineci_runner_alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = data.aws_acm_certificate.pipelineci_runner_certificate.arn

  default_action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.pipelineci_runner_target_group.arn
  }
}

resource "aws_lb_listener_rule" "pipelineci_runner_lb_listener_rule" {
  listener_arn = aws_lb_listener.pipelineci_runner_lb_listener.arn
  priority     = 100

  action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.pipelineci_runner_target_group.arn
  }

  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

resource "aws_security_group" "pipelineci_runner_lb_sg" {
  name        = "pipelineci-runner-lb-sg"
  description = "Security group for Github App alb"

  vpc_id = aws_vpc.pipelineci_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_acm_certificate" "pipelineci_runner_certificate" {
  domain      = "${var.RUNNER_SUBDOMAIN}.${var.DOMAIN_NAME}"
  statuses    = ["ISSUED"]
  most_recent = true
}

resource "aws_lb_listener_certificate" "pipelineci_runner_alb_certificate" {
  listener_arn    = aws_lb_listener.pipelineci_runner_lb_listener.arn
  certificate_arn = data.aws_acm_certificate.pipelineci_runner_certificate.arn
}

resource "aws_route53_record" "pipelineciRunnerRecord" {
  zone_id = data.aws_route53_zone.pipelineciZone.zone_id
  name          = "${var.RUNNER_SUBDOMAIN}.${var.DOMAIN_NAME}"
  type    = "A"

  alias {
    name                    = aws_lb.pipelineci_runner_alb.dns_name
    zone_id                 = aws_lb.pipelineci_runner_alb.zone_id
    evaluate_target_health  = true
  }
}
