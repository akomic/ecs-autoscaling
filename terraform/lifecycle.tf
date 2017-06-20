# Lifecycle
resource "aws_autoscaling_lifecycle_hook" "ec2_ecs_termination" {
  name                   = "tf-${var.ClusterName}-lifecycle-termination-hook"
  autoscaling_group_name = "${aws_autoscaling_group.ecs-asg.name}"
  default_result         = "CONTINUE"
  heartbeat_timeout      = 600
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"

  depends_on             = ["aws_ecs_cluster.ecs", "aws_ecs_task_definition.our_lifecycle_task_definition", "null_resource.local"]
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


# ECS Task IAM
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

# CloudWatch Event Rule
resource "aws_cloudwatch_event_rule" "ecs_lifecycle" {
  name        = "tf-${var.ClusterName}-ecs-lifecycle"
  description = "Capture AutoScaling Termination and drain instances"

  event_pattern = <<PATTERN
{
  "source": [
    "aws.autoscaling"
  ],
  "detail-type": [
    "EC2 Instance-terminate Lifecycle Action"
  ],
  "detail": {
    "AutoScalingGroupName": [
      "${aws_autoscaling_group.ecs-asg.name}"
    ]
  }
}
PATTERN
}

# CloudWatch Event Rule Target IAM
resource "aws_iam_role" "ecs_lifecycle_cloudwatch" {
  name = "tf-${var.ClusterName}-ecs-lifecycle-cloudwatch"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "events.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_lifecycle_cloudwatch_access" {
  name = "tf-${var.ClusterName}-ecs-lifecycle-cloudwatch-policy-access"
  role = "${aws_iam_role.ecs_lifecycle_cloudwatch.name}"
  depends_on = ["aws_cloudwatch_event_rule.ecs_lifecycle"]

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecs:RunTask"
            ],
            "Resource": [
                "${aws_ecs_task_definition.our_lifecycle_task_definition.arn}"
            ],
            "Condition": {
                "ArnEquals": {
                    "ecs:cluster": "${aws_ecs_cluster.ecs.id}"
                }
            }
        }
    ]
}
EOF
}

# CloudWatch Event Target JSON
data "template_file" "cloudwatch_target" {
  template = "${file("${path.module}/cloudwatch-event-rule-target.json")}"

  vars {
    roleARN           = "${aws_iam_role.ecs_lifecycle_cloudwatch.arn}"
    taskDefinitionARN = "${aws_ecs_task_definition.our_lifecycle_task_definition.arn}"
    clusterARN        = "${aws_ecs_cluster.ecs.id}"
    clusterName       = "${aws_ecs_cluster.ecs.name}"
  }

  depends_on = ["aws_ecs_task_definition.our_lifecycle_task_definition", "aws_iam_role_policy.ecs_lifecycle_cloudwatch_access"]
}

resource "null_resource" "local" {
  triggers {
    template = "${data.template_file.cloudwatch_target.rendered}"
  }

  provisioner "local-exec" {
    command = <<EOT
    echo '${data.template_file.cloudwatch_target.rendered}' > /tmp/tf-${var.ClusterName}-ecs-lifecycle-cloudwatch.target.json &&
    aws events put-targets --rule "tf-${var.ClusterName}-ecs-lifecycle" --targets file:///tmp/tf-${var.ClusterName}-ecs-lifecycle-cloudwatch.target.json
EOT
  }
}
