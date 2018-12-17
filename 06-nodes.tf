//  An SSH keypair to access instances.
resource "aws_key_pair" "keypair" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

//  A userdata script for instances.
data "template_file" "node_userdata" {
  template = "${file("${path.module}/files/node_userdata.sh")}"

  vars {
    availability_zone = "todo"
    region = "${var.region}"
    ecs_cluster_name = "${var.ecs_cluster_name}"
  }
}

//  A Launch Configuration for ECS cluster instances.
resource "aws_launch_configuration" "ecs_cluster_node" {

  name_prefix   = "ecs-cluster-node-"
  image_id                    = "${data.aws_ami.latest_ecs.id}"
  instance_type               = "${var.instance_size}"
  iam_instance_profile        = "${aws_iam_instance_profile.ecs-instance-profile.id}"

  root_block_device {
    volume_type = "standard"
    volume_size = 100
    delete_on_termination = true
  }

  //  Recommended for auto-scaling groups and launch configurations.
  lifecycle {
    create_before_destroy = true
  }

  security_groups = ["${concat(
    list(
      aws_security_group.intra_node_communication.id,
      aws_security_group.public_ingress.id,
      aws_security_group.public_egress.id,
      aws_security_group.ssh_access.id
    ),
    var.instance_security_groups
  )}"]

  associate_public_ip_address = "true"
  user_data                   = "${data.template_file.node_userdata.rendered}"
  key_name = "${aws_key_pair.keypair.key_name}"
}

data "null_data_source" "tags" {
  count = "${length(keys(var.tags))}"

  inputs = {
    key                 = "${element(keys(local.tags), count.index)}"
    value               = "${element(values(local.tags), count.index)}"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "ecs_cluster_node" {
  name                        = "ecs_cluster_node"
  min_size                    = "${var.node_count}"
  max_size                    = "${var.node_count}"
  desired_capacity            = "${var.node_count}"
  vpc_zone_identifier         = ["${aws_subnet.public_subnet.*.id}"]
  launch_configuration        = "${aws_launch_configuration.ecs_cluster_node.name}"
  health_check_type           = "ELB"

  //  Recommended for auto-scaling groups and launch configurations.
  lifecycle {
    create_before_destroy = true
  }

  tags = [
    "${data.null_data_source.tags.*.outputs}",
    {
      key = "Name",
      value = "ECS Cluster Instance",
      propagate_at_launch = true 
    }
  ]
}
