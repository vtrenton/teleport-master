resource "aws_s3_bucket" "teleport" {
  bucket = var.s3_bucket_name

  tags = {
    Name = var.s3_bucket_name
  }
}
