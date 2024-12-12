#
# Load Balancer, Github app
#

resource "aws_lb" "pipelineci_ghapp_alb" {
  name                = "pipelineci-ghapp-alb"
  internal            = false
  load_balancer_type  = "application"
  subnets             = [aws_subnet.pipelineci_public_subnet_01.id, aws_subnet.pipelineci_public_subnet_02.id]
  security_groups     = [aws_security_group.pipelineci_ghapp_lb_sg.id]
}

resource "aws_lb_target_group" "pipelineci_ghapp_target_group" {
  name        = "pipelineci-ghapp-target-group"
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

resource "aws_lb_listener" "pipelineci_ghapp_lb_listener" {
  load_balancer_arn = aws_lb.pipelineci_ghapp_alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = data.aws_acm_certificate.pipelineci_ghapp_certificate.arn

  default_action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.pipelineci_ghapp_target_group.arn
  }
}

resource "aws_lb_listener_rule" "pipelineci_ghapp_lb_listener_rule" {
  listener_arn = aws_lb_listener.pipelineci_ghapp_lb_listener.arn
  priority     = 100

  action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.pipelineci_ghapp_target_group.arn
  }

  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

resource "aws_security_group" "pipelineci_ghapp_lb_sg" {
  name        = "pipelineci-ghapp-lb-sg"
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

data "aws_acm_certificate" "pipelineci_ghapp_certificate" {
  domain      = "${var.GHAPP_SUBDOMAIN}.${var.DOMAIN_NAME}"
  statuses    = ["ISSUED"]
  most_recent = true
}

resource "aws_lb_listener_certificate" "pipelineci_ghapp_alb_certificate" {
  listener_arn    = aws_lb_listener.pipelineci_ghapp_lb_listener.arn
  certificate_arn = data.aws_acm_certificate.pipelineci_ghapp_certificate.arn
}

resource "aws_route53_record" "pipelineciGhappRecord" {
  zone_id = data.aws_route53_zone.pipelineciZone.zone_id
  name          = "${var.GHAPP_SUBDOMAIN}.${var.DOMAIN_NAME}"
  type    = "A"

  alias {
    name                    = aws_lb.pipelineci_ghapp_alb.dns_name
    zone_id                 = aws_lb.pipelineci_ghapp_alb.zone_id
    evaluate_target_health  = true
  }
}
