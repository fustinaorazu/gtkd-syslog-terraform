
# Networking (simple public VPC)

resource "aws_vpc" "syslog" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "syslog-vpc" }
}

resource "aws_internet_gateway" "syslog" {
  vpc_id = aws_vpc.syslog.id
  tags   = { Name = "syslog-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.syslog.id
  cidr_block               = "10.10.1.0/24"
  map_public_ip_on_launch  = true
  availability_zone        = "eu-central-1b"

  tags = { Name = "syslog-public-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.syslog.id
  tags   = { Name = "syslog-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.syslog.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group (UDP 514 + optional SSH)
resource "aws_security_group" "syslog" {
  name        = "syslog-sg"
  description = "Allow syslog UDP/514 from internet (demo) + optional SSH"
  vpc_id      = aws_vpc.syslog.id

  # Syslog UDP 514 (public, for the case study)
  ingress {
    description = "Syslog UDP 514"
    from_port   = 514
    to_port     = 514
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "syslog-sg" }
}

# IAM Role for EC2 with the two role i spoke about yesterday (SSM and CloudWatch Agent)

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "syslog_ec2" {
  name               = "syslog-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.syslog_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cwagent" {
  role       = aws_iam_role.syslog_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "syslog" {
  name = "syslog-ec2-profile"
  role = aws_iam_role.syslog_ec2.name
}


# This is my CloudWatch Log Group WITH persistent storage

resource "aws_cloudwatch_log_group" "syslog" {
  name              = "/aws/syslog/central-ingest"
  retention_in_days = 5
}


# This is the EC2 (Amazon Linux 2023)

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "syslog" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.syslog.id]
  iam_instance_profile        = aws_iam_instance_profile.syslog.name
  associate_public_ip_address = true


  user_data = file("${path.module}/user-data/cloud-init.yaml")


  tags = { Name = "Syslog" }

  depends_on = [aws_cloudwatch_log_group.syslog]
}

output "public_ip" {
  value = aws_instance.syslog.public_ip
}

output "public_dns" {
  value = aws_instance.syslog.public_dns
}
