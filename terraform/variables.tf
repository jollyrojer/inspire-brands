variable "vpc_id" {
  default = "vpc-2b93eb43"
}

variable "subnet_ids" {
  default = ["subnet-22ee4358","subnet-b83f4bd0","subnet-e34a5aae"]
}

variable "aws_availability_zones" {
  default = ""
}

variable "aws_vault_ami" {
  default = "ami-0921edafb48de1f46"
}

variable "aws_bastion_host_ami" {
  default = "ami-0ffc6be916b97da8a"
}
