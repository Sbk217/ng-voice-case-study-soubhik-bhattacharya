
data "aws_instances" "node1" {
  filter {
    name   = "tag:eks:cluster-name"
    values = [var.cluster_name]
  }
  filter {
    name   = "availability-zone"
    values = ["eu-central-1a"]
  }
  instance_state_names = ["running"]
}

resource "aws_subnet" "multus" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.10.64.0/24"
  availability_zone = "eu-central-1a"
  tags              = { Name = "multus-casestudy-sbox-1a" }
}

resource "aws_route_table_association" "multus" {
  subnet_id      = aws_subnet.multus.id
  route_table_id = var.private_route_table_ids[0]
}

resource "aws_security_group" "multus" {
  name   = "multus-casestudy-sbox"
  vpc_id = var.vpc_id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.10.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface" "multus" {
  subnet_id       = aws_subnet.multus.id
  security_groups = [aws_security_group.multus.id]
  # .10 = ENI primary IP, .11-.13 reserved for pods (VPC must own pod IPs or it drops traffic)
  private_ips     = ["10.10.64.10", "10.10.64.11", "10.10.64.12", "10.10.64.13"]
  tags = {
    "node.k8s.amazonaws.com/no_manage" = "true" # tells VPC CNI: hands off this ENI
  }
}

resource "aws_network_interface_attachment" "multus" {
  instance_id          = data.aws_instances.node1.ids[0]
  network_interface_id = aws_network_interface.multus.id
  device_index         = var.device_index
}