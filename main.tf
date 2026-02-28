# 1. Primary VPC (Production)
resource "aws_vpc" "primary" {
  provider             = aws.primary
  cidr_block           = var.primary_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "WAK-PRIMARY-VPC", Env = "Production" }
}

# 2. Secondary VPC (Disaster Recovery)
resource "aws_vpc" "secondary" {
  provider             = aws.secondary
  cidr_block           = var.secondary_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "WAK-DR-VPC", Env = "Disaster-Recovery" }
}

# 3. Subnets
resource "aws_subnet" "primary_pub" {
  provider   = aws.primary
  vpc_id     = aws_vpc.primary.id
  cidr_block = "10.1.1.0/24"
  tags       = { Name = "Primary-Public-Subnet" }
}

resource "aws_subnet" "secondary_pub" {
  provider   = aws.secondary
  vpc_id     = aws_vpc.secondary.id
  cidr_block = "10.2.1.0/24"
  tags       = { Name = "DR-Public-Subnet" }
}

# 4. PRIVATE HOSTED ZONE
resource "aws_route53_zone" "internal" {
  provider = aws.primary
  name     = "wakwetu.internal"
  vpc {
    vpc_id = aws_vpc.primary.id
  }
  vpc {
    vpc_id = aws_vpc.secondary.id
    vpc_region = "us-west-2"
  }
}

# 5. GLOBAL HEALTH CHECK
resource "aws_route53_health_check" "primary_check" {
  provider          = aws.primary
  type              = "TCP"
  ip_address        = "8.8.8.8" 
  port              = 81
  failure_threshold = "3"
  request_interval  = "30"
  tags              = { Name = "WAK-PRIMARY-HEALTH-CHECK" }
}

# 6. PRIMARY DNS RECORD
resource "aws_route53_record" "primary_dns" {
  provider = aws.primary
  zone_id  = aws_route53_zone.internal.zone_id
  name     = "app.wakwetu.internal"
  type     = "A"
  failover_routing_policy { type = "PRIMARY" }
  set_identifier = "primary-region"
  health_check_id = aws_route53_health_check.primary_check.id
  ttl     = 60
  records = ["10.1.1.10"] 
}

# 7. SECONDARY DNS RECORD
resource "aws_route53_record" "secondary_dns" {
  provider = aws.secondary
  zone_id  = aws_route53_zone.internal.zone_id
  name     = "app.wakwetu.internal"
  type     = "A"
  failover_routing_policy { type = "SECONDARY" }
  set_identifier = "secondary-region"
  ttl     = 60
  records = ["10.2.1.10"] 
}

# 8. PRIMARY DATA BUCKET
resource "aws_s3_bucket" "primary_data" {
  provider      = aws.primary
  bucket        = "wakwetu-primary-data-vault-1772316755"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "primary_vars" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary_data.id
  versioning_configuration { status = "Enabled" }
}

# 9. SECONDARY DATA BUCKET
resource "aws_s3_bucket" "secondary_data" {
  provider      = aws.secondary
  bucket        = "wakwetu-dr-data-replica-1772316755"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "secondary_vars" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary_data.id
  versioning_configuration { status = "Enabled" }
}

# 10. REPLICATION IAM ROLE
resource "aws_iam_role" "replication" {
  name = "wakwetu-s3-replication-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "replication" {
  name = "wakwetu-s3-replication-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Effect = "Allow"
        Resource = [aws_s3_bucket.primary_data.arn]
      },
      {
        Action = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl"]
        Effect = "Allow"
        Resource = ["${aws_s3_bucket.primary_data.arn}/*"]
      },
      {
        Action = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Effect = "Allow"
        Resource = ["${aws_s3_bucket.secondary_data.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

# 11. ENABLING REPLICATION
resource "aws_s3_bucket_replication_configuration" "replication" {
  provider = aws.primary
  depends_on = [aws_s3_bucket_versioning.primary_vars]
  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.primary_data.id
  rule {
    id     = "GlobalDataReplication"
    status = "Enabled"
    destination {
      bucket        = aws_s3_bucket.secondary_data.arn
      storage_class = "STANDARD"
    }
  }
}
