# Lifecycle
resource "aws_autoscaling_lifecycle_hook" "ec2_ecs_termination" {
  name                   = "tf-${var.ClusterName}-lifecycle-termination-hook"
  autoscaling_group_name = "${aws_autoscaling_group.ecs-asg.name}"
  default_result         = "CONTINUE"
  heartbeat_timeout      = 600
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"

  depends_on             = ["aws_ecs_cluster.ecs", "aws_ecs_task_definition.our_lifecycle_task_definition"]

  notification_metadata = <<EOF
{
  "ClusterARN": "${aws_ecs_cluster.ecs.id}",
  "TaskDefinition": "${aws_ecs_task_definition.our_lifecycle_task_definition.arn}"
}
EOF
}

# ECS Task
data "template_file" "our_lifecycle_task" {
  template = "${file("${path.module}/task-definition.json")}"

  vars = {
    ASG_NAME = "${aws_autoscaling_group.ecs-asg.name}"
    CLUSTER_ARN = "${aws_ecs_cluster.ecs.id}"
    TERMINATION_HOOK_NAME = "tf-${var.ClusterName}-lifecycle-termination-hook"
  }
}

resource "aws_ecs_task_definition" "our_lifecycle_task_definition" {
  family = "tf-${var.ClusterName}-lifecycle"
  container_definitions = "${data.template_file.our_lifecycle_task.rendered}"
  task_role_arn = "${aws_iam_role.ecs_lifecycle_task.arn}"
}


# IAM
resource "aws_iam_role" "ecs_lifecycle_task" {
  name = "tf-${var.ClusterName}-ecs-lifecycle"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ecs-tasks.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_lifecycle_task_access" {
  name = "tf-${var.ClusterName}-ecs-lifecycle-task-policy-access"
  role = "${aws_iam_role.ecs_lifecycle_task.name}"
  depends_on = ["aws_ecs_task_definition.our_lifecycle_task_definition", "aws_iam_role.ecs_lifecycle_task"]

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecs:RunTask",
                "ecs:DescribeClusters",
                "ecs:DescribeContainerInstances",
                "ecs:DescribeTaskDefinition",
                "ecs:ListContainerInstances",
                "ecs:UpdateContainerInstancesState"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:CompleteLifecycleAction",
                "autoscaling:DescribeScalingActivities"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF
}
