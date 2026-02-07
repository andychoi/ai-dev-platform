output "bucket_arns" {
  description = "Map of bucket key to ARN"
  value = {
    for key, bucket in aws_s3_bucket.this : key => bucket.arn
  }
}

output "bucket_names" {
  description = "Map of bucket key to name"
  value = {
    for key, bucket in aws_s3_bucket.this : key => bucket.id
  }
}
