output "bucket" {
    value = aws_s3_bucket.s3_bucket
}

output "instance_profile" {
    value = aws_iam_instance_profile.intance_profile
}