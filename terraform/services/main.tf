provider "aws" {
  region = local.region
}

locals {
  name   = "apicurio-service"
  region = "eu-west-2"

  container_registry_name = "apicurio-registry"
  container_registry_port = 8081

  container_ui_name = "apicurio-ui"
  container_ui_port = 8080

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/ecs-blueprints"
  }
}

module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.6"

  name          = local.name
  desired_count = 1
  cluster_arn   = data.aws_ecs_cluster.apicurio_cluster.arn

  cpu = 500
  memory = 900

  # Task Definition
  enable_execute_command   = true
  requires_compatibilities = ["EC2"]
  capacity_provider_strategy = {
    default = {
      capacity_provider = "apicurio-registry" # needs to match name of capacity provider
      weight            = 1
      base              = 1
    }
  }

  container_definitions = {
    (local.container_registry_name) = {
      name = local.container_registry_name
      image                    = "docker.io/apicurio/apicurio-registry:3.0.6"
      readonly_root_filesystem = false

      cpu = 500
      memory = 900

      port_mappings = [
        {
          protocol      = "tcp",
          containerPort = local.container_registry_port
        }
      ]

      environment = [
        {
          name  = "QUARKUS_HTTP_PORT",
          value = "8081"
        },
        {
          name  = "QUARKUS_HTTP_CORS_ORIGINS",
          value = "*"
        },
      ]
    }
  }

  service_registries = {
    registry_arn = aws_service_discovery_service.this.arn
  }

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["ecs-task-registry"].arn
      container_name   = local.container_registry_name
      container_port   = local.container_registry_port
    }
  }

  subnet_ids = data.aws_subnets.private.ids
  security_group_rules = {
    alb_ingress = {
      type                     = "ingress"
      from_port                = local.container_registry_port
      to_port                  = local.container_registry_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb.security_group_id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = local.tags
}

module "ecs_service_ui" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.6"

  name          = "${local.name}-ui"
  desired_count = 1
  cluster_arn   = data.aws_ecs_cluster.apicurio_cluster.arn

  cpu = 500
  memory = 900

  # Task Definition
  enable_execute_command   = true
  requires_compatibilities = ["EC2"]
  capacity_provider_strategy = {
    default = {
      capacity_provider = "apicurio-registry" # needs to match name of capacity provider
      weight            = 1
      base              = 1
    }
  }

  container_definitions = {
    (local.container_ui_name) = {
      name = local.container_ui_name
      image                    = "docker.io/apicurio/apicurio-registry-ui:3.0.6"
      readonly_root_filesystem = false

      cpu = 500
      memory = 900
      user = 1001

      port_mappings = [
        {
          protocol      = "tcp",
          containerPort = local.container_ui_port
        }
      ]

      environment = [
        {
          name  = "REGISTRY_API_URL",
          value = "$APICURIO_API_URL"
        }
      ]
    }
  }

  service_registries = {
    registry_arn = aws_service_discovery_service.this.arn
  }

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["ecs-task"].arn
      container_name   = local.container_ui_name
      container_port   = local.container_ui_port
    }
  }

  subnet_ids = data.aws_subnets.private.ids
  security_group_rules = {
    alb_ingress = {
      type                     = "ingress"
      from_port                = local.container_ui_port
      to_port                  = local.container_ui_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb.security_group_id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = local.tags
}

resource "aws_service_discovery_service" "this" {
  name = local.name

  dns_config {
    namespace_id = data.aws_service_discovery_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name = local.name

  # For example only
  enable_deletion_protection = false

  vpc_id  = data.aws_vpc.vpc.id
  subnets = data.aws_subnets.public.ids
  security_group_ingress_rules = {
    all_http = {
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  # Allows all outgoing traffic (TCP)
    }
  }

  security_group_egress_rules = {

  }

  listeners = {
    http = {
      port     = "443"
      protocol = "HTTPS"

      ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
      certificate_arn   = "arn:aws:acm:eu-west-2:992382478497:certificate/b83a6d0b-a3c0-4f6b-89db-b3f7c5fa5519"

      forward = {
        target_group_key = "ecs-task-registry"
      }

      rules = {
        ui = {
          priority = 20
          actions = [
            {
              type                       = "authenticate-cognito"
              on_unauthenticated_request = "authenticate"
              session_cookie_name        = "AWSELBAuthSessionCookie"
              session_timeout            = 3600
              user_pool_arn              = data.aws_cognito_user_pool.cognito_pool.arn
              user_pool_client_id        = "3rtbhqdslnir5kaumagetm16p1"
              user_pool_domain           = data.aws_cognito_user_pool.cognito_pool.domain
            },
            {
            type = "weighted-forward"
            target_groups = [
              {
                target_group_key = "ecs-task"
                weight           = 1
              }
            ]
          }]

          conditions = [{
            host_header = {
              values = ["ui2.ikenna.dev"]
            }
          }]
        }
      }
    }
  }

  target_groups = {
    ecs-task = {
      backend_protocol = "HTTP"
      backend_port     = local.container_ui_port
      target_type      = "ip"

      health_check = {
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        matcher             = "200-299"
        path                = "/"
        port                = "8080"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 10
      }

      # There's nothing to attach here in this definition. Instead,
      # ECS will attach the IPs of the tasks to this target group
      create_attachment = false
    }

    ecs-task-registry = {
      backend_protocol = "HTTP"
      backend_port     = local.container_registry_port
      target_type      = "ip"

      health_check = {
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        matcher             = "200-299"
        path                = "/health"
        port                = "8081"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 10
      }

      # There's nothing to attach here in this definition. Instead,
      # ECS will attach the IPs of the tasks to this target group
      create_attachment = false
    }
  }

  tags = local.tags
}

resource "aws_route53_record" "cname_route53_record" {
  zone_id = "Z0005177FICW1B4G2709"
  name    = "$APICURIO_API_DOMAIN"
  type    = "CNAME"
  ttl     = "60"
  records = [module.alb.dns_name]
}

resource "aws_route53_record" "cname_route53_record_ui" {
  zone_id = "Z0005177FICW1B4G2709"
  name    = "$APICURIO_UI_DOMAIN"
  type    = "CNAME"
  ttl     = "60"
  records = [module.alb.dns_name]
}

################################################################################
# Supporting Resources
################################################################################

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = ["apicurio-registry"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Name"
    values = ["apicurio-registry-public-*"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Name"
    values = ["apicurio-registry-private-*"]
  }
}

data "aws_subnet" "private_cidr" {
  for_each = toset(data.aws_subnets.private.ids)
  id       = each.value
}

data "aws_ecs_cluster" "apicurio_cluster" {
  cluster_name = "apicurio-registry"
}

data "aws_cognito_user_pool" "cognito_pool" {
  user_pool_id = "eu-west-2_s5uw7yjCP"
}

data "aws_service_discovery_dns_namespace" "this" {
  name = "default.${data.aws_ecs_cluster.apicurio_cluster.cluster_name}.local"
  type = "DNS_PRIVATE"
}
