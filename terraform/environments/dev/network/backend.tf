terraform {
  backend "s3" {
    # bucket comes from terraform/backend.hcl (gitignored). Generate:
    #   ./scripts/write-backend-config.sh
    key            = "petclinic/dev/network/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
    profile        = "petclinic"
  }
}
