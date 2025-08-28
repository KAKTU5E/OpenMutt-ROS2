#!/usr/bin/env python3
import csv
import rclpy
from sensor_msgs.msg import Imu  # Correct message type for IMU data

rclpy.init_node('imuData_listener', anonymous=True)
rate = rclpy.Rate(2)
csv_file_path = 'imuOutPut.csv'

# Open the CSV file in append mode
csv_file = open(csv_file_path, mode='a', newline='')
writer = csv.writer(csv_file)

def callback(data):
    # Extract linear acceleration values
    linear_acceleration = data.linear_acceleration
    ax = round(linear_acceleration.x, 3)
    ay = round(linear_acceleration.y, 3)
    az = round(linear_acceleration.z, 3)
    
    # Write to CSV
    writer.writerow([ax, ay, az])
    print(f"Linear Acceleration: ax={ax}, ay={ay}, az={az}")

def listener():
    rclpy.Subscriber("/imu/data", Imu, callback, queue_size=1)
    print("Subscriber set up to /imu/data")  # Debugging statement
    rclpy.spin()

if __name__ == '__main__':
    print("Starting listener node...")  # Debugging statement
    listener()