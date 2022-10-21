# provider "aws" {
# }
# provider "aws" {
#   # CUR is only available in us-east-1.
#   # aws_cur_report_definition.this is the only resource using this provider.
#   alias = "cur"
# }
#  region = "us-east-1"

/*   assume_role {
    role_arn     = var.cur_role_arn
    session_name = var.cur_role_session_name
  } */
#}

terraform {
  required_providers {
  aws = {
        source = "hashicorp/aws"
        configuration_aliases = [aws,aws.cur]
    }
  }
}
#   required_providers {
#     aws-cur = {
#       source  = "hashicorp/aws-cur"
#       version = ">= 2.7.0"
#     }
#     aws = {
#       source  = "hashicorp/aws"
#       version = ">= 2.7.0"
#     }
#   }

