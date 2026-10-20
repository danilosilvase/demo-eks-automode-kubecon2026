# Private-only access to the EKS API (no public endpoint, nothing inbound from the internet).
# A tiny SSM-managed instance in a private subnet (no public IP, no inbound SG rules)
# is used as the far end of an SSM port-forward to the private API endpoint.

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_iam_role" "ssm_access" {
  name = "${local.name}-ssm-access"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_access.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_access" {
  name = "${local.name}-ssm-access"
  role = aws_iam_role.ssm_access.name
}

resource "aws_security_group" "ssm_access" {
  name        = "${local.name}-ssm-access"
  description = "SSM port-forward host. No inbound rules."
  vpc_id      = module.vpc.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}

resource "aws_instance" "ssm_access" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.value
  instance_type               = "t4g.nano"
  subnet_id                   = module.vpc.private_subnets[0]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm_access.name
  vpc_security_group_ids      = [aws_security_group.ssm_access.id]
  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    encrypted = true
  }
  tags = merge(var.tags, { Name = "${local.name}-ssm-access" })
}

# Let the access host reach the private API endpoint on 443
resource "aws_security_group_rule" "api_from_ssm_primary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.eks.cluster_primary_security_group_id
  source_security_group_id = aws_security_group.ssm_access.id
  description              = "EKS API from SSM access host"
}
