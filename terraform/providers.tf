provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "mrp-analytics-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
      Track       = "B"
    }
  }
}
