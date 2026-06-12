# Remote state backend — created by bootstrap.sh, never by Terraform itself.
terraform {
  backend "s3" {
    bucket         = "govplatform-tfstate-445358171352"
    key            = "govplatform/dev/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "govplatform-tflock"
    encrypt        = true
    profile        = "govplatform-dev"
  }
}
