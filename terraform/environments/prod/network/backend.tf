terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-833123247984"
    key            = "petclinic/prod/network/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
    profile        = "petclinic"
  }
}
