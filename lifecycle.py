#!/usr/bin/env python

import re
import os
import time
import boto3


class ASGHandler():
    def __init__(self, asgName, clusterARN, hookName):
        self.asgName = asgName
        self.clusterARN = clusterARN
        self.hookName = hookName

        self.toTerminate = {}
        self.notified = {}

        self.autoscaling = boto3.client('autoscaling',
                                        region_name='us-east-1')
        self.ecs = boto3.client('ecs', region_name='us-east-1')

    def __drain_instances(self):
        toDrain = []
        for ec2InstanceId in self.toTerminate:
            print "Draining instance: {0}".format(ec2InstanceId)
            toDrain.append(
                self.toTerminate[ec2InstanceId]['containerInstanceArn']
            )

        self.ecs.update_container_instances_state(
            cluster=self.clusterARN,
            containerInstances=toDrain,
            status='DRAINING'
        )

    def __update_instance_info(self):
        print "Fetch terminating instances info for {0} ... [{1}]".format(
            self.clusterARN, len(self.toTerminate))
        cInstances = self.ecs.list_container_instances(
            cluster=self.clusterARN
        )

        response = self.ecs.describe_container_instances(
            cluster=self.clusterARN,
            containerInstances=cInstances['containerInstanceArns']
        )

        for cInstance in response['containerInstances']:
            if cInstance['ec2InstanceId'] in self.toTerminate:
                self.toTerminate[cInstance['ec2InstanceId']] = {
                    'containerInstanceArn': cInstance['containerInstanceArn'],
                    'pendingTasksCount': cInstance['pendingTasksCount'],
                    'runningTasksCount': cInstance['runningTasksCount'],
                    'status': cInstance['status']
                }
                self.containerInstanceARN = cInstance['containerInstanceArn']

    def __find_terminating_instances(self):
        print "Finding instances waiting for termination ..."
        response = self.autoscaling.describe_scaling_activities(
            AutoScalingGroupName=self.asgName,
            MaxRecords=20
        )

        activities = response['Activities']

        for activity in activities:
            if activity['StatusCode'] == 'MidTerminatingLifecycleAction':
                m = re.search('^Terminating EC2 instance:\s+(i\-.*)$',
                              activity['Description'])
                if m:
                    ec2InstanceId = m.group(1).strip()
                    self.toTerminate[ec2InstanceId] = {}

        return len(self.toTerminate)

    def __handle_termination(self):
        self.__update_instance_info()
        waiting = 0
        for ec2InstanceId in self.toTerminate:
            if ec2InstanceId in self.notified:
                continue

            ref = self.toTerminate[ec2InstanceId]
            if ref['status'] != 'DRAINING':
                continue

            if ref['pendingTasksCount'] == 0 and ref['runningTasksCount'] == 0:
                print "Sending CONTINUE: {0} {1} {2}".format(
                    self.hookName,
                    self.asgName,
                    ec2InstanceId
                )
                self.autoscaling.complete_lifecycle_action(
                    LifecycleHookName=self.hookName,
                    AutoScalingGroupName=self.asgName,
                    LifecycleActionResult='CONTINUE',
                    InstanceId=ec2InstanceId
                )
                self.notified[ec2InstanceId] = True
            else:
                waiting += 1

        return waiting

    def run(self):
        if self.__find_terminating_instances() > 0:
            self.__update_instance_info()
            self.__drain_instances()
            while True:
                time.sleep(10)
                print "Ping!"
                if self.__handle_termination() == 0:
                    print "My work here is DONE!"
                    break
        else:
            print "Can't find any instances waiting for draining. Done!"


if __name__ == "__main__":
    asg = ASGHandler(
        os.getenv('ASG_NAME'),
        os.getenv('CLUSTER_ARN'),
        os.getenv('TERMINATION_HOOK_NAME')
    )
    asg.run()
