#TODO : Consider  deadletter queues. Code signing

locals {
  lambda_function_name = "${var.report_name}-crawler-trigger"
}

resource "aws_s3_bucket_notification" "cur" {
  bucket = var.s3_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.run_crawler.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "${var.s3_bucket_prefix}/"
    filter_suffix       = ".parquet"
  }

  depends_on = [
    aws_s3_bucket.cur,
    aws_lambda_permission.allow_bucket,
    aws_s3_bucket_policy.cur,
  ]
}

resource "aws_lambda_function" "run_crawler" {
	# checkov:skip=CKV_AWS_116: Dead-Letter-Handling - Come back to putting errors on a queue and notifying.
	# checkov:skip=CKV_AWS_117: This isn't sensitive and we have no VPC's in play so do we really need to put it in a VPC?
	# checkov:skip=CKV_AWS_173: we're ok to use the default service key for encryption https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function#kms_key_arn
  # checkov:skip=CKV_AWS_272: Ensure AWS Lambda function is configured to validate code-signing - looking for a pattern to fix this
  function_name = local.lambda_function_name

  role = aws_iam_role.lambda.arn

  runtime          = "nodejs12.x"
  handler          = "index.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
  reserved_concurrent_executions = 5

  environment {
    variables = {
      CRAWLER_NAME = aws_glue_crawler.this.name
    }
  }
   tracing_config {
     mode = "Active"
   }
  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/src/index.js"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id   = "AllowExecutionFromS3Bucket"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.run_crawler.arn
  source_account = data.aws_caller_identity.current.account_id
  principal      = "s3.amazonaws.com"
  source_arn     = var.use_existing_s3_bucket ? data.aws_s3_bucket.cur[0].arn : aws_s3_bucket.cur[0].arn
}

resource "aws_iam_role" "lambda" {
  name               = "${var.report_name}-crawler-trigger"
  assume_role_policy = data.aws_iam_policy_document.crawler_trigger_assume.json
}

resource "aws_iam_role_policy" "lambda" {
  role   = aws_iam_role.lambda.name
  policy = data.aws_iam_policy_document.crawler_trigger.json
}

data "aws_iam_policy_document" "crawler_trigger_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "crawler_trigger" {
  statement {
    sid = "CloudWatch"

    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid = "Glue"

    effect = "Allow"

    actions = [
      "glue:StartCrawler",
      "glue:GetSecurityConfiguration",
    ]

    resources = [aws_glue_crawler.this.arn]
  }
}

# Pre-create log group for the Lambda function.
# Otherwise it will be created by Lambda itself with infinite retention.
#
# Accept default encryption. This Lambda does not produce sensitive logs.
#tfsec:ignore:aws-cloudwatch-log-group-customer-key
# checkov:skip=CKV_AWS_158: Not sensitive

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.lambda_log_group_retention_days

}
