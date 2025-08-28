#!/usr/bin/env python3
import csv
import rclpy
from trajectory_msgs.msg import JointTrajectory
from std_msgs.msg import String

rclpy.init_node('joint_command_listener', anonymous=True)
rate = rclpy.Rate(2)
csv_file_path = 'legOutPut.csv'

# Open the CSV file in append mode
csv_file = open(csv_file_path, mode='a', newline='')
writer = csv.writer(csv_file)




def callback(data):
    #joint_names = data.joint_names
    positions = list(data.points[0].positions)
    for ii in range(len(positions)):
         positions[ii] = float(round(positions[ii], 3))

    #Leg 1 (Front Left)
    hipX = positions[0] #hipX
    hipY = positions[1] #hipY
    Knee = positions[2] #knee
    angles = [hipX, hipY, Knee]
    writer.writerow(angles)
    print(angles)





     
def listener():
    rclpy.Subscriber("/joint_group_position_controller/command", JointTrajectory, callback, queue_size=1)
    rclpy.spin()


while not rclpy.is_shutdown():
        listener()
