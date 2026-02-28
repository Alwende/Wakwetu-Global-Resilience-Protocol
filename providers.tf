terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Primary Region (North Virginia)
provider "aws" {
  alias  = "primary"
  region = "us-east-1"
}

# Secondary Region (Oregon)
provider "aws" {
  alias  = "secondary"
  region = "us-west-2"
}
