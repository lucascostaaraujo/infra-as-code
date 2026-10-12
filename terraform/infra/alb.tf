# ---------------------------------------------------------------------------
# Application Load Balancer (publico, nas 2 subnets), roteamento por host:
#   var.keycloak_hostname -> Keycloak,  var.gatus_hostname -> Gatus.
# Qualquer outro Host recebe 404.
#
# - enable_https = false: so HTTP:80 (fase 1, ate o certificado ser validado).
# - enable_https = true: 443 com o certificado ACM; 80 redireciona para 443.
# ---------------------------------------------------------------------------

locals {
  scheme = var.enable_https ? "https" : "http"
  # Listener que recebe as regras por host
  main_listener_arn = var.enable_https ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}

resource "aws_lb" "this" {
  name               = var.alb_name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = merge(local.common_tags, {
    Name = var.alb_name
  })
}

# --- Target groups (tasks Fargate => target_type = ip) ----------------------

resource "aws_lb_target_group" "keycloak" {
  name        = "${var.cluster_name}-keycloak"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  deregistration_delay = 30

  health_check {
    path                = "/realms/master"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "gatus" {
  name        = "${var.cluster_name}-gatus"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.common_tags
}

# --- Listeners ---------------------------------------------------------------

# HTTP:80 - 404 padrao (as regras por host ficam aqui na fase 1) ou redirect
# para HTTPS (fase 2)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.enable_https ? "redirect" : "fixed-response"

    dynamic "redirect" {
      for_each = var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "fixed_response" {
      for_each = var.enable_https ? [] : [1]
      content {
        content_type = "text/plain"
        message_body = "Not found"
        status_code  = "404"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.this.arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

# --- Regras por host -----------------------------------------------------------

resource "aws_lb_listener_rule" "keycloak" {
  listener_arn = local.main_listener_arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.keycloak.arn
  }

  condition {
    host_header {
      values = [var.keycloak_hostname]
    }
  }
}

resource "aws_lb_listener_rule" "gatus" {
  listener_arn = local.main_listener_arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gatus.arn
  }

  condition {
    host_header {
      values = [var.gatus_hostname]
    }
  }
}
