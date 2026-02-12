#In real situation, i will uses variables for reusability across environments (e.g., dev/stage/prod)
variable "aws_region" {
  type    = string
  default = "eu-central-1"
}
#this was the profile i created when i link terraform with my AWS
variable "aws_profile" {
  type    = string
  default = "shopware"
}