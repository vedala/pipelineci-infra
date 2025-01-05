
#
# Bastion Host
#

resource "aws_security_group" "pipelineci_bastion_sg" {
  name        = "pipelineci-bastion-sg"
  description = "Security group for the pipelineci bastion host"
  vpc_id      = aws_vpc.pipelineci_vpc.id

  ingress {
    description = "Allow SSH access from specific IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.SELF_IP_FOR_BASTION]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "amazon_bastion_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

data "aws_key_pair" "pipelineci_bastion_key_pair" {
  key_name           = var.BASTION_KEY_PAIR_NAME
  include_public_key = true
}

resource "aws_eip" "pipelineci_bastion_eip" {
  vpc               = true
}

resource "aws_eip_association" "pipelineci_bastion_eip_association" {
  instance_id   = aws_instance.pipelineci_bastion.id
  allocation_id = aws_eip.pipelineci_bastion_eip.id
}

resource "aws_spot_instance_request" "pipelineci_bastion" {
  ami             = data.aws_ami.amazon_bastion_ami.id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.pipelineci_public_subnet_01.id
  key_name        = data.aws_key_pair.pipelineci_bastion_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.pipelineci_bastion_sg.id]

  spot_type       = "one-time"
  spot_price      = var.BASTION_SPOT_PRICE

  tags = {
    Name = "pipelineci-bastion-host"
  }
}
