output "bucket_names" {
  value = {
    primary   = { for k, b in aws_s3_bucket.primary : k => b.bucket }
    secondary = { for k, b in aws_s3_bucket.secondary : k => b.bucket }
  }
}
