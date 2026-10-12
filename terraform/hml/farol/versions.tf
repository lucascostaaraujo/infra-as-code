terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Ajuste/descomente conforme o backend usado no restante do repo.
  # backend "s3" {
  #   bucket = "SEU_BUCKET_DE_STATE"
  #   key    = "hml/farol/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.region
}
