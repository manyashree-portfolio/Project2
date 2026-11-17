# State lives in Mumbai. The state bucket must itself be replicated to Hyderabad,
# versioned, and protected with Object Lock (RB-11 improvement action).
# Bucket, table and key alias are placeholders: replace before `terraform init`.
terraform {
  backend "s3" {
    bucket         = "paysecure-tfstate-mum"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "paysecure-tflock"
    encrypt        = true
    kms_key_id     = "alias/paysecure-data"
  }
}
