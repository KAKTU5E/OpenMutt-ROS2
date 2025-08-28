#!/usr/bin/env python3
import socket
import rclpy
import time
import asyncio
import json
from trajectory_msgs.msg import JointTrajectory
from std_msgs.msg import String

rclpy.init_node('joint_command_listener', anonymous=True)
rate = rclpy.Rate(2)

#Class (sorry Dylan and Ethan)
class Leg:
    def __init__(self, joint1=None, joint2=None, joint3=None):
        self.joint1 = joint1
        self.joint2 = joint2
        self.joint3 = joint3

leg1 = Leg(0, 0, 0)
leg2 = Leg(0, 0, 0)
leg3 = Leg(0, 0, 0)
leg4 = Leg(0, 0, 0)

SERVER_IP = '192.168.1.10'
SERVER_PORT = 3333
client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
client_socket.connect((SERVER_IP, SERVER_PORT))

last = time.time()

def send_data_sync(data):
    try:
        client_socket.send(data.encode())
    except Exception as e:
        rclpy.logerr(f"Failed to send message: {e}")


def callback(data):
    global last
    interval = .01
    #joint_names = data.joint_names
    positions = list(data.points[0].positions)
    for ii in range(len(positions)):
         positions[ii] = float(round(positions[ii], 3))

    #Leg 1 (Front Left)
    leg1.joint1 = positions[0] #hipX
    leg1.joint2 = positions[1] #hipY
    leg1.joint3 = positions[2] #knee

    #Leg 2 (Front Right)
    leg2.joint1 = positions[3] #hipX
    leg2.joint2 = positions[4] #hipY
    leg2.joint3 = positions[5] #knee

    #Leg 3 (Back Left)
    leg3.joint1 = positions[6] #hipX
    leg3.joint2 = positions[7] #hipY
    leg3.joint3 = positions[8] #knee

    #Leg 4 (Back Right)
    leg4.joint1 = positions[9] #hipX
    leg4.joint2 = positions[10] #hipY
    leg4.joint3 = positions[11] #knee


    legsData = {
    'joint11': leg1.joint1,
    'joint12': leg1.joint2,
    'joint13': leg1.joint3,
    'joint21': leg2.joint1,
    'joint22': leg2.joint2,
    'joint23': leg2.joint3,
    'joint31': leg3.joint1,
    'joint32': leg3.joint2,
    'joint33': leg3.joint3,
    'joint41': leg4.joint1,
    'joint42': leg4.joint2,
    'joint43': leg4.joint3
    }

    print(legsData)
    json_data = json.dumps(legsData)
    # Send the MessagePack bytes over the socket
    now = time.time()
    if now > last + interval:
        print(len(json_data))
        send_data_sync(json_data)
        last = now

                
#def socketSend(posStr):
    #rclpy.loginfo("Sending command:")
    #client_socket.sendall(posStr.encode())
    #print(posStr)
    #await asyncio.sleep(0)

     
def listener():
    rclpy.Subscriber("/joint_group_position_controller/command", JointTrajectory, callback, queue_size=1)
    rclpy.spin()
    #rate.sleep()
    
    #await asyncio.sleep(0)


while not rclpy.is_shutdown():
        listener()
