# ---------------------------------------------------------------------------
# Liga/desliga automatico de recursos com a tag autoOnOff=true.
#
# 1 Lambda (lambda/autooff/handler.py) que descobre os recursos marcados via
# Resource Groups Tagging API e liga/desliga (hoje: EC2 e RDS, os unicos tipos
# com estado start/stop de verdade). 2 schedules no EventBridge Scheduler,
# seg-sex, horario de Brasilia (America/Sao_Paulo - sem DST desde 2019, entao
# o cron nao precisa de ajuste sazonal):
#   - 07:00 BRT -> action=start
#   - 19:00 BRT -> action=stop
#
# A EC2 (aws_instance.pd_adata, em main.tf) e o RDS (aws_db_instance.postgrescarrier,
# em rds.tf) ja tem a tag autoOnOff=true.
# ---------------------------------------------------------------------------

data "archive_file" "autooff" {
  type        = "zip"
  source_file = "${path.module}/lambda/autooff/handler.py"
  output_path = "${path.module}/lambda/autooff.zip"
}

# --- IAM: execucao da Lambda ----------------------------------------------
data "aws_iam_policy_document" "autooff_lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "autooff_lambda" {
  name               = "pd-adata-autooff-lambda"
  assume_role_policy = data.aws_iam_policy_document.autooff_lambda_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "autooff_lambda_basic" {
  role       = aws_iam_role.autooff_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "autooff_lambda_permissions" {
  statement {
    sid       = "TaggingRead"
    actions   = ["tag:GetResources"]
    resources = ["*"]
  }

  statement {
    sid = "Ec2StartStop"
    actions = [
      "ec2:DescribeInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
    ]
    resources = ["*"]
  }

  statement {
    sid = "RdsStartStop"
    actions = [
      "rds:DescribeDBInstances",
      "rds:StartDBInstance",
      "rds:StopDBInstance",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "autooff_lambda_permissions" {
  name   = "pd-adata-autooff-permissions"
  role   = aws_iam_role.autooff_lambda.id
  policy = data.aws_iam_policy_document.autooff_lambda_permissions.json
}

# --- Lambda -----------------------------------------------------------
resource "aws_lambda_function" "autooff" {
  function_name = "carrier-auto-on-off"
  role          = aws_iam_role.autooff_lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.13"
  timeout       = 60

  filename         = data.archive_file.autooff.output_path
  source_code_hash = data.archive_file.autooff.output_base64sha256

  tags = local.common_tags
}

# --- IAM: EventBridge Scheduler invocando a Lambda ------------------------
data "aws_iam_policy_document" "autooff_scheduler_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "autooff_scheduler" {
  name               = "pd-adata-autooff-scheduler"
  assume_role_policy = data.aws_iam_policy_document.autooff_scheduler_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "autooff_scheduler_invoke" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.autooff.arn]
  }
}

resource "aws_iam_role_policy" "autooff_scheduler_invoke" {
  name   = "pd-adata-autooff-invoke"
  role   = aws_iam_role.autooff_scheduler.id
  policy = data.aws_iam_policy_document.autooff_scheduler_invoke.json
}

# --- Schedules: 07:00 (start) e 19:00 (stop), seg-sex, horario de Brasilia --
resource "aws_scheduler_schedule" "autooff_start" {
  name = "pd-adata-autooff-start"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 7 ? * MON-FRI *)"
  schedule_expression_timezone = "America/Sao_Paulo"

  target {
    arn      = aws_lambda_function.autooff.arn
    role_arn = aws_iam_role.autooff_scheduler.arn
    input    = jsonencode({ action = "start" })
  }
}

resource "aws_scheduler_schedule" "autooff_stop" {
  name = "pd-adata-autooff-stop"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 19 ? * MON-FRI *)"
  schedule_expression_timezone = "America/Sao_Paulo"

  target {
    arn      = aws_lambda_function.autooff.arn
    role_arn = aws_iam_role.autooff_scheduler.arn
    input    = jsonencode({ action = "stop" })
  }
}
