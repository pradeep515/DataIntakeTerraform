provider "aws" {
  region  = var.region
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "healthcare-vpc"
  cidr = "10.0.0.0/16"
  azs  = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
  one_nat_gateway_per_az = false
}

resource "aws_ecs_cluster" "cluster" {
  name = "healthcare-ecs-cluster"
}
#ami-03afdcc08c89cd0b8
resource "aws_launch_template" "ecs_ec2" {
  name_prefix   = "ecs-ec2-"
  image_id      = "ami-03afdcc08c89cd0b8" 
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.cluster.name} >> /etc/ecs/ecs.config
              EOF
  )

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ecs_sg.id]
  }
}

resource "aws_autoscaling_group" "ecs_asg" {
  vpc_zone_identifier = module.vpc.private_subnets
  desired_capacity    = 1
  min_size           = 1
  max_size           = 2

  launch_template {
    id      = aws_launch_template.ecs_ec2.id
    version = "$Latest"
  }
}

resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs_instance_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs_instance_profile"
  role = aws_iam_role.ecs_instance_role.name
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs_task_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  role = aws_iam_role.ecs_task_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = [
          "arn:aws:dynamodb:us-east-1:*:table/intake-customerrecords",
          "arn:aws:dynamodb:us-east-1:*:table/intake-processedfiles"
        ]
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["ecr:*"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["ssm:*"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs_sg"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "alb_sg"
  vpc_id      = module.vpc.vpc_id
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

resource "aws_lb" "alb" {
  name               = "healthcare-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "frontend_tg" {
  name        = "frontend-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check {
    path = "/"
    port = "3000"
  }
}

resource "aws_lb_target_group" "middle_tier_tg" {
  name        = "middle-tier-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check {
    path = "/healthcheck/"
    port = "8000"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
}

resource "aws_lb_listener_rule" "middle_tier_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.middle_tier_tg.arn
  }

  condition {
    path_pattern {
      values = ["/items/*", "/health/*"]
    }
  }
}

resource "aws_ecr_repository" "frontend" {
  name = "frontend-repo"
  force_delete = true 
}

resource "aws_ecr_repository" "middle_tier" {
  name = "middle-tier-repo"
  force_delete = true 
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "frontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"  # 0.5 vCPU
  memory                   = "2048" # 2 GiB
  execution_role_arn       = aws_iam_role.ecs_task_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = "${aws_ecr_repository.frontend.repository_url}:latest"
      cpu       = 512
      memory    = 1024  # Hard limit for container
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]
      command = [
  "reflex", "run"
      ]
      environment = [
        { name = "MIDDLE_TIER_URL", value = "http://${aws_lb.alb.dns_name}" }
      ]
      secrets = [
        { name = "API_KEY", valueFrom =  aws_secretsmanager_secret.api_key.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/frontend-task"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "middle_tier" {
  family                   = "middle-tier-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name  = "middle-tier"
    image = "${aws_ecr_repository.middle_tier.repository_url}:latest"
    portMappings = [{ containerPort = 8000, hostPort = 8000 }]
    essential = true
    command = ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
    environment = [
      { name = "AWS_REGION", value = "us-east-1" },
      { name = "DYNAMODB_TABLE_NAME", value = "intake-customerrecords" }
    ]
    secrets = [
      { name = "API_KEY", valueFrom = aws_secretsmanager_secret.api_key.arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/middle-tier-task"
        "awslogs-region"        = "us-east-1"
        "awslogs-stream-prefix" = "middle-tier"
      }
    }
  }])
}

resource "aws_ecs_service" "frontend" {
  name            = "frontend-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.frontend.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend_tg.arn
    container_name   = "frontend"
    container_port   = 3000
  }
}
# depends_on = [aws_lb_listener.http]

resource "aws_ecs_service" "middle_tier" {
  name            = "middle-tier-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.middle_tier.arn
  desired_count   = 0
  launch_type     = "EC2"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.middle_tier_tg.arn
    container_name   = "middle-tier"
    container_port   = 8000
  }
}

resource "aws_cloudwatch_log_group" "frontend_log_ecs" {
  name              = "/ecs/frontend-task"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "middle_tier_log_group" {
  name              = "/ecs/middle-tier-task"
  retention_in_days = 7
}

# Secrets Manager for API_KEY
resource "aws_secretsmanager_secret" "api_key" {
  name = "middle-tier-api-key"
}

resource "aws_secretsmanager_secret_version" "api_key_version" {
  secret_id     = aws_secretsmanager_secret.api_key.id
  secret_string = "test"
}

resource "aws_iam_role_policy" "ecs_task_secrets_policy" {
  role = aws_iam_role.ecs_task_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.api_key.arn]
      },
      {
        Effect = "Allow"
        Action = ["ssm:*"]
        Resource = [aws_secretsmanager_secret.api_key.arn]
      }
    ]
  })
}