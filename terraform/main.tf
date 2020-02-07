provider "aws" {
  profile = "inspire-brands-sandbox" 
  region = "eu-west-2"
}

#
# SECURITY GROUPS
#

resource "aws_security_group" "bastion-host-sg" {
  name = "bastion-host-sg"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vault-lb-sg"{
  name = "vault-lb-sg"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vault-service-sg"{
  name = "vault-service-sg"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = ["${aws_security_group.bastion-host-sg.id}"]
  }
  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    security_groups = ["${aws_security_group.vault-lb-sg.id}"]
  }
}

#
# ALB frontend 
#

# Create ALB

resource "aws_lb" "vault-alb" {
  name = "vault-service-alb"
  internal = false
  load_balancer_type = "application"
  security_groups = ["${aws_security_group.vault-lb-sg.id}"]
  subnets = ["var.subnet_ids"]
  enable_deletion_protection = false
}

resource "aws_alb_target_group" "vault-service-alb-tg" {
  name = "vault-service-target-group"
  port = 80
  protocol = "HTTP"
  vpc_id = "var.vpc_id"
  target_type = "instance"
  health_check {
    protocol = "HTTP"
    path = "/"
    port = "traffic-port"
    healthy_threshold = 5
    unhealthy_threshold = 2
    timeout = 5
    interval = 30
    matcher = "200"
  }
}

# Create ALB HTTPS Listener
resource "aws_alb_listener" "vault-service-listener" {
  load_balancer_arn = "aws_lb.vault-alb.arn"
  port = 8200
  protocol = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "aws_lb_target_group.vault-service-alb-tg.arn"
  }
}

############################
### Bastion Host AutoScaling ###
############################

# Launch configuration
resource "aws_launch_configuration" "bastion-host-launch-config" {
  name = "bastion-host"
  image_id = "ami-0ffc6be916b97da8a"
  instance_type = "t2.micro"
  key_name = "bastion-host"
  security_groups = ["${aws_security_group.bastion-host-sg.id}"]
  enable_monitoring = true
}

# Auto scaling group
resource "aws_autoscaling_group" "bastion-host-scailing-group" {
  name = "bastion-host"
  launch_configuration = "aws_launch_configuration.bastion-host-launch-config.name"
  max_size = 1
  min_size = 1
  desired_capacity = 1
  health_check_type = "EC2"
  health_check_grace_period = "30"
}

# Autoscaling notifications
resource "aws_autoscaling_notification" "bastion-host-scaling-notifications" {
  group_names = [
    "${aws_autoscaling_group.bastion-host-scailing-group.name}"
  ]
  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR"
  ]
  topic_arn = "var.aws_sns_topic"
}

# Autoscaling policy
resource "aws_autoscaling_policy" "bastion-host-scaling-policy" {
  autoscaling_group_name = "aws_autoscaling_group.bastion-host-scailing-group.name"
  name = "bastion-host-sp"
  scaling_adjustment = 1
  adjustment_type = "ExactCapacity"
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = "aws_instance.bastion-host.id"
  allocation_id = "aws_eip.bastion-host-eip.id"
}

resource "aws_eip" "bastion-host-eip" {
  vpc = true
}

############################
### Vault Host AutoScaling #
############################
# Launch configuration
resource "aws_launch_configuration" "vault-service-launch-config" {
  name = "vault-service"
  image_id = "var.aws_vault_ami"
  instance_type = "t2.micro"
  key_name = "vault-ssh-key"
  security_groups = ["aws_security_group.vault-service-sg.id"]
  enable_monitoring = true
}

# Auto scaling group
resource "aws_autoscaling_group" "vault-service-scailing-group" {
  name = "vault-service"
  launch_configuration = "aws_launch_configuration.vault-service-launch-config.name"
  max_size = 2
  min_size = 2
  desired_capacity = 2
  health_check_type = "EC2"
  health_check_grace_period = "30"
}

# Autoscaling notifications
resource "aws_autoscaling_notification" "vault-service-scaling-notifications" {
  group_names = [
    "aws_autoscaling_group.vault-service-scailing-group.name"
  ]
  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR"
  ]
  topic_arn = "var.aws_sns_topic"
}

# Autoscaling policy
resource "aws_autoscaling_policy" "vault-service-scaling-policy" {
  autoscaling_group_name = "aws_autoscaling_group.vault-service-scailing-group.name"
  name = "vault-service"
  scaling_adjustment = 3
  adjustment_type = "ExactCapacity"
}

# Add Scaling Group to ALB
resource "aws_autoscaling_attachment" "vault-service-as-attachement" {
  autoscaling_group_name = "aws_autoscaling_group.vault-service-scailing-group.id"
  alb_target_group_arn   = "aws_alb_target_group.vault-service-tg.arn"
}

#
# S3 BUCKET VAULT BACKEND
#
resource "aws_s3_bucket" "vault-backend" {
  bucket = "vault-backend"
  acl    = "private"

  tags = {
    Name        = "Vault backend"
    Environment = "vault-demo"
  }
}
