output "primary_dns_status" {
  value = aws_route53_record.primary_dns.records
}

output "secondary_dns_status" {
  value = aws_route53_record.secondary_dns.records
}

output "health_check_id" {
  value = aws_route53_health_check.primary_check.id
}
