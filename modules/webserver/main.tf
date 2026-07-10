# ==============================================================================
# SECURITY GROUPS
# ==============================================================================
resource "aws_security_group" "ec2-sg" {
  name        = "${var.env_prefix}-ec2-sg"
  vpc_id      = var.vpc_id
  description = "Allow ALB to reach EC2 application tier"

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env_prefix}-ec2-sg" }
}

# ==============================================================================
# COMPUTE BLUEPRINT AMIs & KEYS
# ==============================================================================
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = [var.image_name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "ssh-key" {
  key_name   = "${var.env_prefix}-server-key"
  public_key = var.public_key_content
}

# ==============================================================================
# ENGINE TEMPLATE & RUNTIME EXECUTION
# ==============================================================================
resource "aws_launch_template" "web_server_lt" {
  name_prefix   = "${var.env_prefix}-web-server-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.ssh-key.key_name

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2-sg.id]
  }

  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  # FIXED PATHING: Reads script safely relative to root or module scope via clean variable injection
  user_data = filebase64("${path.root}/entry-script.sh")

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.env_prefix}-asg-instance"
      SSM  = "Enabled"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ==============================================================================
# FLEET AUTO SCALING MANAGEMENT
# ==============================================================================
resource "aws_autoscaling_group" "web_asg" {
  # FIXED NAMING: Appending the unique Launch Template name_prefix prevents collision errors on update
  name_prefix         = "${var.env_prefix}-web-asg-"
  vpc_zone_identifier = var.private_subnet_ids
  desired_capacity    = var.desired_capacity
  max_size            = var.max_size
  min_size            = var.min_size

  target_group_arns = [var.target_group_arn]

  launch_template {
    id      = aws_launch_template.web_server_lt.id
    version = aws_launch_template.web_server_lt.latest_version
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  # OPTIMIZATION: Enables rolling replacement configurations without dropping cluster availability
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["tag"]
  }

  tag {
    key                 = "Name"
    value               = "${var.env_prefix}-asg-node"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}