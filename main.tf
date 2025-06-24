# ECR Repository to push images
resource "aws_ecr_repository" "my-html-repo" {
  name = "my-html-repo"
}

# ECS Cluster - a group of Containers
resource "aws_ecs_cluster" "my-html-cluster" {
  name = "my-html-cluster"
}

# ECS Task Definition to define the behaviour of task
resource "aws_ecs_task_definition" "my-task-def" {
  family                = "my-html-task-definition"
  container_definitions = <<DEFINITION
  [
    {
        "name" : "my-html-container",
        "image" :  "${aws_ecr_repository.my-html-repo.repository_url}",
        "essential" : true,
        "portMappings": [
            {
                "containerPort" : 80,
                "hostPort" : 80 
            }
        ],
        "memory" : 512,
        "cpu" : 256
    }
  ]
  DEFINITION

  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = aws_iam_role.my-html-role.arn
}
# Role to execute the ecs tasks
resource "aws_iam_role" "my-html-role" {
  name               = "my-html-role-ecs"
  assume_role_policy = data.aws_iam_policy_document.my-html-assumtion.json
}

data "aws_iam_policy_document" "my-html-assumtion" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "my-html-policy" {
  role       = aws_iam_role.my-html-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# VPC
resource "aws_vpc" "my-html-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "my-html-vpc"
  }
}
locals {
  cidr_blocks        = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zones = ["ap-south-1a", "ap-south-1b"]
}

# Subnets
resource "aws_subnet" "my-html-subnets" {
  vpc_id                  = aws_vpc.my-html-vpc.id
  count                   = 2
  cidr_block              = local.cidr_blocks[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "my-html-subnet-${count.index}"
  }
}

#IGW
resource "aws_internet_gateway" "my-html-igw" {
  vpc_id = aws_vpc.my-html-vpc.id
  tags = {
    Name = "my-html-IGW"
  }
}

# Route table
resource "aws_route_table" "my-html-rt" {
  vpc_id = aws_vpc.my-html-vpc.id
  tags = {
    Name = "my-html-rt"
  }
}

# Route
resource "aws_route" "my-html-rt" {
  route_table_id         = aws_route_table.my-html-rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.my-html-igw.id
}

# Route Association
resource "aws_route_table_association" "my-html-association" {
  count          = 2
  route_table_id = aws_route_table.my-html-rt.id
  subnet_id      = aws_subnet.my-html-subnets[count.index].id

}

# ALB
resource "aws_alb" "my-html-alb" {
  name               = "my-html-alb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.my-html-subnets[0].id, aws_subnet.my-html-subnets[1].id]
  security_groups    = [aws_security_group.my-html-alb-sg.id]
}


# Target Group
resource "aws_alb_target_group" "my-html-target" {
  name        = "my-html-target"
  vpc_id      = aws_vpc.my-html-vpc.id
  target_type = "instance"
  port        = 80
  protocol    = "HTTP"
}

# Listener
resource "aws_alb_listener" "name" {
  load_balancer_arn = aws_alb.my-html-alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.my-html-target.arn
  }
}

# Security Group for ALB
resource "aws_security_group" "my-html-alb-sg" {
  vpc_id = aws_vpc.my-html-vpc.id
  name   = "my-html-alb-sg"
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

# ECS Service
resource "aws_ecs_service" "my-html-ecs" {
  name            = "my-html-ecs-service"
  cluster         = aws_ecs_cluster.my-html-cluster.id
  task_definition = aws_ecs_task_definition.my-task-def.arn
  launch_type     = "EC2"
  desired_count   = 2
  load_balancer {
    target_group_arn = aws_alb_target_group.my-html-target.arn
    container_name   = "my-html-container"
    container_port   = 80
  }

}


# Security Group for the instances that will get launched

resource "aws_security_group" "my-html-ecs-sg" {
  name   = "my-html-ecs-sg"
  vpc_id = aws_vpc.my-html-vpc.id
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.my-html-alb-sg.id]

  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Role to access ECS
resource "aws_iam_role" "my-html-ec2-role" {
  name               = "my-html-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.my-ec2-policy.json
}

data "aws_iam_policy_document" "my-ec2-policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "my-html-ec2-attach" {
  role       = aws_iam_role.my-html-ec2-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "my-html-ec2-profile" {
  name = "ecs-instance-profile"
  role = aws_iam_role.my-html-ec2-role.name
}

# Data block to fetch the ECS supported AMI

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# Launch template for the ASG
resource "aws_launch_template" "my-ec2-launch" {
  name_prefix   = "my-html-ecs-template-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t2.micro"
  user_data = base64encode(<<EOF
  #!/bin/bash
  echo "ECS_CLUSTER=${aws_ecs_cluster.my-html-cluster.name}" >> /etc/ecs/ecs.config
  EOF
  )
  key_name               = "Mac_Login"
  vpc_security_group_ids = [aws_security_group.my-html-ecs-sg.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.my-html-ec2-profile.name
  }
}

# ASG 
resource "aws_autoscaling_group" "my-html-asg" {
  name             = "my-html-asg"
  desired_capacity = 2
  min_size         = 2
  max_size         = 4
  launch_template {
    id      = aws_launch_template.my-ec2-launch.id
    version = "$Latest"
  }
  vpc_zone_identifier = [aws_subnet.my-html-subnets[0].id, aws_subnet.my-html-subnets[1].id]
  tag {
    key                 = "name"
    value               = "my-ins"
    propagate_at_launch = true
  }
}
