provider "aws" {
  region = var.region

  dynamic "assume_role" {
    for_each = var.deploy_role_arn == null ? [] : [1]

    content {
      role_arn     = var.deploy_role_arn
      session_name = var.deploy_role_session_name
    }
  }

}
