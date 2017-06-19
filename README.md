# ECS Task for AutoScaling Scale-In instance Draining and termination

When AutoScaling decides that instance has to be terminated, it proceeds
with the termination regardless of the tasks running on the instance. This
results in disruption of service, which is a feature missing in AWS
ecosystem.

To alleviate this the following is done:

- AutoScaling lifecycle termination hook created with Terraform.
This will stop termination of the instance with AutoScaling Status Code set
to 'MidTerminatingLifecycleAction' until complete_lifecycle_action with
LifecycleActionResult=CONTINUE is not sent.
- CloudWatch Events Rule
Rule is hooked up to AutoScaling instance termination hook for particular
autoscaling group. Target of this rule is to run already defined task with
Terraform (which containes necessary information to drain affected instance)
- ECS Task
goes through all instances of the AutoScaling group which are
in waiting termination status, than correlates those with ECS cluster
instances and sets DRAINING status for each. It than checks every several
seconds if number of running and pending containers on the instance reached
0 and than sends CONTINUE signal to AutoScaling so it can proceed with the
instance termination.

## What we need
- ECS Task definition
- Role
```
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
```
- IAM policy attached to ECS Task def to allow the following:
```
      "ecs:RunTask",
      "ecs:DescribeClusters",
      "ecs:DescribeContainerInstances",
      "ecs:DescribeTaskDefinition",
      "ecs:ListContainerInstances",
      "ecs:UpdateContainerInstancesState"
      "autoscaling:CompleteLifecycleAction",
      "autoscaling:DescribeScalingActivities"
```
- CloudWatch Event Rule

## Creating docker image for ECS Task
- Edit
  - Makefile
  - .release

- Run
```
$ make all
```
