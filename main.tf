terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
  profile =  "kv97usr1"
}

locals {
  az_count = 2
  public_subnets = [
    aws_subnet.pipelineci_public_subnet_01, aws_subnet.pipelineci_public_subnet_02
  ]
  private_subnets = [
    aws_subnet.pipelineci_private_subnet_01, aws_subnet.pipelineci_private_subnet_02
  ]
}

#
# VPC
#

resource "aws_vpc" "pipelineci_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "pipelineci_public_subnet_01" {
  vpc_id            = aws_vpc.pipelineci_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "pipelineci_public_subnet_01"
  }
}

resource "aws_subnet"  "pipelineci_public_subnet_02" {
  vpc_id            = aws_vpc.pipelineci_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "pipelineci_public_subnet_02"
  }
}

resource "aws_subnet"  "pipelineci_private_subnet_01" {
  vpc_id            = aws_vpc.pipelineci_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "pipelineci_private_subnet_01"
  }
}

resource "aws_subnet"  "pipelineci_private_subnet_02" {
  vpc_id            = aws_vpc.pipelineci_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "pipelineci_private_subnet_02"
  }
}

resource "aws_internet_gateway" "pipelineci_igw" {
  vpc_id = aws_vpc.pipelineci_vpc.id
}

resource "aws_route_table" "pipelineci_public_rt" {
  vpc_id = aws_vpc.pipelineci_vpc.id
}

resource "aws_route" "pipelineci_public_route" {
  route_table_id          = aws_route_table.pipelineci_public_rt.id
  destination_cidr_block  = "0.0.0.0/0"
  gateway_id              = aws_internet_gateway.pipelineci_igw.id
}

resource "aws_route_table_association" "pipelineci_subnet_association_pub01" {
  subnet_id       = aws_subnet.pipelineci_public_subnet_01.id
  route_table_id  = aws_route_table.pipelineci_public_rt.id
}

resource "aws_route_table_association" "pipelineci_subnet_association_pub02" {
  subnet_id       = aws_subnet.pipelineci_public_subnet_02.id
  route_table_id  = aws_route_table.pipelineci_public_rt.id
}

data "aws_availability_zones" "avail_zones" {}

data "aws_ami" "amazon_nat_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn-ami-vpc-nat-*-x86_64-ebs"]
  }
}

resource "aws_autoscaling_group" "pipelineci_nat_inst" {
  count              = "${local.az_count}"
  name               = "nat-inst-asg-${count.index}"
  desired_capacity   = 1
  min_size           = 1
  max_size           = 1
  availability_zones = ["${element(data.aws_availability_zones.avail_zones.names, count.index)}"]

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
    }

    launch_template {
      launch_template_specification {
        launch_template_id = "${element(aws_launch_template.pipelineci_nat_inst.*.id, count.index)}"
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = ["t2.micro"]

        content {
          instance_type = "${override.value}"
        }
      }
    }
  }
}

resource "aws_security_group" "pipelineci_nat_inst_sg" {
  name        = "pipelineci-nat-inst-sg"
  description = "Security group for NAT instances"

  vpc_id = aws_vpc.pipelineci_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  # ingress {
  #   from_port   = 1024
  #   to_port     = 65535
  #   protocol    = "tcp"
  #   cidr_blocks = [aws_subnet.pipelineci_private_subnet_01.cidr_block, aws_subnet.pipelineci_private_subnet_02.cidr_block]
  # }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.pipelineci_private_subnet_01.cidr_block, aws_subnet.pipelineci_private_subnet_02.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface" "pipelineci_nat_eni" {
  count             = "${local.az_count}"
  security_groups   = ["${aws_security_group.pipelineci_nat_inst_sg.id}"]
  subnet_id         = local.public_subnets[count.index].id
  source_dest_check = false
}

resource "aws_eip" "pipelineci_eip" {
  count             = "${local.az_count}"
  vpc               = true
  network_interface = "${element(aws_network_interface.pipelineci_nat_eni.*.id, count.index)}"
}

resource "aws_launch_template" "pipelineci_nat_inst" {
  count       = "${local.az_count}"
  name_prefix = "nat-instance-${count.index}"
  image_id    = "${data.aws_ami.amazon_nat_ami.id}"

  network_interfaces {
    delete_on_termination = false
    network_interface_id  = "${element(aws_network_interface.pipelineci_nat_eni.*.id, count.index)}"
  }
}

resource "aws_route_table" "pipelineci_private_rt" {
  count  = "${local.az_count}"
  vpc_id = "${aws_vpc.pipelineci_vpc.id}"
}

resource "aws_route_table_association" "pipelineci_subnet_association_private" {
  count           = "${local.az_count}"
  subnet_id       = local.private_subnets[count.index].id
  route_table_id  = "${element(aws_route_table.pipelineci_private_rt.*.id, count.index)}"
}

resource "aws_route" "pipelineci_private_route" {
  count                  = "${local.az_count}"
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = "${element(aws_route_table.pipelineci_private_rt.*.id, count.index)}"
  network_interface_id   = "${element(aws_network_interface.pipelineci_nat_eni.*.id, count.index)}"
}

#
# Load Balancer
#

resource "aws_lb" "pipelineci_alb" {
  name                = "pipelineci-alb"
  internal            = false
  load_balancer_type  = "application"
  subnets             = [aws_subnet.pipelineci_public_subnet_01.id, aws_subnet.pipelineci_public_subnet_02.id]
  security_groups     = [aws_security_group.pipelineci_lb_sg.id]
}

resource "aws_lb_target_group" "pipelineci_target_group" {
  name        = "pipelineci-target-group"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.pipelineci_vpc.id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = 3000
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-499"
  }
}

resource "aws_lb_listener" "pipelineci_lb_listener" {
  load_balancer_arn = aws_lb.pipelineci_alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = data.aws_acm_certificate.pipelineci_certificate.arn

  default_action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.pipelineci_target_group.arn
  }
}

resource "aws_lb_listener_rule" "pipelineci_lb_listener_rule" {
  listener_arn = aws_lb_listener.pipelineci_lb_listener.arn
  priority     = 100

  action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.pipelineci_target_group.arn
  }

  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

resource "aws_security_group" "pipelineci_lb_sg" {
  name        = "pipelineci-lb-sg"
  description = "Security group for alb"

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

data "aws_acm_certificate" "pipelineci_certificate" {
  domain      = "${var.SUBDOMAIN}.${var.DOMAIN_NAME}"
  statuses    = ["ISSUED"]
  most_recent = true
}

resource "aws_lb_listener_certificate" "pipelineci_alb_certificate" {
  listener_arn    = aws_lb_listener.pipelineci_lb_listener.arn
  certificate_arn = data.aws_acm_certificate.pipelineci_certificate.arn
}

data "aws_route53_zone" "pipelineciZone" {
  name          = "${var.DOMAIN_NAME}."   // a dot appended
  private_zone  = false
}

resource "aws_route53_record" "pipelineciRecord" {
  zone_id = data.aws_route53_zone.pipelineciZone.zone_id
  name          = "${var.SUBDOMAIN}.${var.DOMAIN_NAME}"
  type    = "A"

  alias {
    name                    = aws_lb.pipelineci_alb.dns_name
    zone_id                 = aws_lb.pipelineci_alb.zone_id
    evaluate_target_health  = true
  }
}

#
# Database
#

resource "aws_db_instance" "pipelineci_db" {
  allocated_storage    = 20
  db_name              = "pipelinci_db"
  engine               = "postgres"
  engine_version       = "16.3"
  instance_class       = "db.t3.micro"
  username             = "ciadmin"
  password             = var.DB_PASSWORD
  publicly_accessible  = false
  skip_final_snapshot  = true

  vpc_security_group_ids = [aws_security_group.pipelineci_rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.pipelineci_postgres_subnet_group.name

  tags = {
    Name = "PipelineciPostgresDb"
  }
}

resource "aws_db_subnet_group" "pipelineci_postgres_subnet_group" {
  name       = "pipelineci-pg-subnet-group"
  subnet_ids = [
    aws_subnet.pipelineci_private_subnet_01.id,
    aws_subnet.pipelineci_private_subnet_02.id
  ]

  tags = {
    Name = "PipelineciPostgresSubnetGroup"
  }
}

resource "aws_security_group" "pipelineci_rds_sg" {
  name        = "pipelineci-rds-security-group"
  description = "Security group for RDS"

  vpc_id      = aws_vpc.pipelineci_vpc.id

  ingress {
    description     = "Allow ECS service to access RDS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.pipelineci_ecs_service_sg.id, aws_security_group.pipelineci_ecs_migrations_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "pipelineci_db" {
  value       = aws_db_instance.pipelineci_db.endpoint
  description = "Database endpoint"
}

#
# ECS
#

resource "aws_ecs_cluster" "pipelineci_cluster" {
  name = "pipelineci-fargate-cluster"
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ecs_execution_policy" {
  name = "ecs_execution_policy"
  description = "ECS Execution Policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:StopTask",
          "ecs:StartTask",
          "ecs:RunTask",
        ],
        Effect   = "Allow",
        Resource = "*",
      },
      {
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:GetRepositoryPolicy",
          "ecr:BatchGetImage",
        ],
        Effect   = "Allow",
        Resource = "*",
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Effect   = "Allow",
        Resource = "*",
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_attachment" {
  policy_arn  = aws_iam_policy.ecs_execution_policy.arn
  role        = aws_iam_role.ecs_execution_role.name
}

resource "aws_cloudwatch_log_group" "pipelineci_log_group" {
  name              = "/ecs/pipelineci-backend"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "pipelineci_task_definition" {
  family                    = "pipelineci-fargate-task"
  network_mode              = "awsvpc"
  requires_compatibilities  = ["FARGATE"]
  execution_role_arn        = aws_iam_role.ecs_execution_role.arn
  cpu                       = "256"
  memory                    = "512"

  container_definitions = jsonencode([
    {
      name  = "pipelineci-container",
      image = "888577039580.dkr.ecr.us-west-2.amazonaws.com/pipelineci-backend:0.1",
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
          awslogs-group         = aws_cloudwatch_log_group.pipelineci_log_group.name
          awslogs-region        = "us-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    },
  ])
}

resource "aws_ecs_service" "pipelineci_service" {
  name            = "pipelineci-fargate-service"
  cluster         = aws_ecs_cluster.pipelineci_cluster.id
  task_definition = aws_ecs_task_definition.pipelineci_task_definition.arn
  desired_count   = 2
  # launch_type     = "FARGATE"

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets           = [aws_subnet.pipelineci_private_subnet_01.id, aws_subnet.pipelineci_private_subnet_02.id]
    security_groups   = [aws_security_group.pipelineci_ecs_service_sg.id]
    assign_public_ip  = false
  }

  load_balancer {
    target_group_arn  = aws_lb_target_group.pipelineci_target_group.arn
    container_name    = "pipelineci-container"
    container_port    = 3000
  }

  depends_on = [
                aws_ecs_task_definition.pipelineci_task_definition,
                aws_lb_target_group.pipelineci_target_group
              ]
}

resource "aws_security_group" "pipelineci_ecs_service_sg" {
  name        = "pipelineci-ecs-service-sg"
  description = "Security group for ECS service"

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
