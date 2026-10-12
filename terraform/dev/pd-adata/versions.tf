terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Ajuste/descomente conforme o backend usado no restante do repo.
  # backend "s3" {
  #   bucket = "SEU_BUCKET_DE_STATE"
  #   key    = "dev/pd-adata/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region  = var.region
  profile = "aws-carrier"
}
