locals {
  # This is defined by AWS.
  glue_log_group_default_name = "/aws-glue/crawlers"
}

# Provisions Glue Crawler and Catalog Database.
# Crawler will, when run, populate the Catalog Database with a table representing the CUR data in S3.

resource "aws_glue_security_configuration" "gluesec" {
  name = "gluesec1"

  encryption_configuration {
    cloudwatch_encryption {
        cloudwatch_encryption_mode = "DISABLED"
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn        = var.s3_use_existing_kms_key ? data.aws_kms_key.s3[0].arn : aws_kms_key.s3[0].arn
      #job_bookmarks_encryption_mode = "DISABLED"
    }

    s3_encryption {
      kms_key_arn        = var.s3_use_existing_kms_key ? data.aws_kms_key.s3[0].arn : aws_kms_key.s3[0].arn
      s3_encryption_mode = "SSE-KMS"
      #s3_encryption_mode = "DISABLED"
    }
  }
}


resource "aws_glue_crawler" "this" {
  name          = "cur-crawler"
  database_name = aws_glue_catalog_database.cur.name
  role          = aws_iam_role.crawler.name
  security_configuration = "gluesec1"

  s3_target {
    path = "s3://${var.s3_bucket_name}/${var.s3_bucket_prefix}/${var.report_name}/${var.report_name}"
  }

  tags = var.tags

  depends_on = [aws_s3_bucket.cur]
}

resource "aws_glue_catalog_database" "cur" {
  name        = "${var.report_name}-db"
  description = "Contains CUR data based on contents from the S3 bucket '${var.s3_bucket_name}'"
}

# Crawler role
resource "aws_iam_role" "crawler" {
  name_prefix        = "cur-crawler"
  assume_role_policy = data.aws_iam_policy_document.crawler_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy" "crawler" {
  role   = aws_iam_role.crawler.name
  policy = data.aws_iam_policy_document.crawler.json
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role   = aws_iam_role.crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

data "aws_iam_policy_document" "crawler_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "crawler" {
  statement {
    sid = "S3Decrypt"

    effect = "Allow"

    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "kms:Encrypt",
    ]

    resources = [var.s3_use_existing_kms_key ? data.aws_kms_key.s3[0].arn : aws_kms_key.s3[0].arn]
  }

/*   statement {
    sid = "Glue"

    effect = "Allow"

    actions = [
      "glue:ImportCatalogToGlue",
      "glue:GetDatabase",
      "glue:UpdateDatabase",
      "glue:GetTable",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:BatchGetPartition",
      "glue:UpdatePartition",
      "glue:BatchCreatePartition",
      "glue:GetSecurityConfiguration",
    ]

    resources = [ 
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      ,aws_glue_catalog_database.cur.arn 
     ]
  }

  statement {
    sid = "CloudWatch"

    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:CreateLogGroup",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.glue_log_group_default_name}",
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.glue_log_group_default_name}:log-stream:*",
    ]
  }
 */
  statement {
    sid = "S3"

    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      "${var.use_existing_s3_bucket ? data.aws_s3_bucket.cur[0].arn : aws_s3_bucket.cur[0].arn}",
      "${var.use_existing_s3_bucket ? data.aws_s3_bucket.cur[0].arn : aws_s3_bucket.cur[0].arn}/*",
    ]
  }
}

# Optionally pre-create log group for Glue Crawlers.
# Crawlers share Log Group for whatever reason I do not know.
#
# Anyway, Crawlers will automatically create this Log Group
# with infinite retention, which is not desirable.
# This gives module consumers the option of letting this module create it/manage it.
#
# Accept default encryption. Crawler logs are not sensitive.
#tfsec:ignore:AWS089
resource "aws_cloudwatch_log_group" "crawler" {
	# checkov:skip=CKV_AWS_158: No sensitive info held
  count = var.glue_crawler_create_log_group ? 1 : 0
  name              = local.glue_log_group_default_name
  retention_in_days = var.glue_crawler_log_group_retention_days
}
