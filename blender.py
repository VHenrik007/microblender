import bpy
import bpy.mathutils as mathutils
from math import radians
import socket
import json
import threading
import time

OUTPUT_DATA_RATE = 50  # Hz

class RotationReceiver:
    def __init__(self, host='127.0.0.1', port=65432):
        self.host = host
        self.port = port
        self.latest_rotation = {'x': 0.0, 'y': 0.0, 'z': 0.0}
        self.running = True

    def start(self):
        self.thread = threading.Thread(target=self.receive_data)
        self.thread.daemon = True
        self.thread.start()

    def receive_data(self):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind((self.host, self.port))
            s.listen()
            s.settimeout(1.0)  # seconds
            print(f"Listening for rotation data on port {self.port}")

            while self.running:
                try:
                    conn, addr = s.accept()
                    with conn:
                        print(f"Connected by {addr}")
                        while self.running:
                            data = conn.recv(1024)
                            if not data:
                                break
                            try:
                                rotation_data = json.loads(data.decode())
                                self.latest_rotation = rotation_data
                            except json.JSONDecodeError:
                                print("Received invalid JSON data")
                except socket.timeout:
                    continue
                except Exception as e:
                    print(f"Error: {e}")
                    time.sleep(1)

class CubeRotationOperator(bpy.types.Operator):
    bl_idname = "object.rotate_cube_from_socket"
    bl_label = "Rotate Cube From Socket"

    _timer = None

    def __init__(self):
        super().__init__()
        self.receiver = RotationReceiver()

    def modal(self, context, event):
        if event.type == 'ESC':
            self.cancel(context)
            return {'CANCELLED'}

        if event.type == 'TIMER':
            try:
                cube = bpy.data.objects['Cube']
            except KeyError:
                self.report({'ERROR'}, "Default cube not found. Please add a cube to the scene.")
                self.cancel(context)
                return {'CANCELLED'}
            # Convert Euler angles to quaternion to avoid gimbal lock
            # this will be useful for the time when magnetometer data is added.
            rotation = mathutils.Euler((
                radians(self.receiver.latest_rotation['x']),
                radians(self.receiver.latest_rotation['y']),
                radians(self.receiver.latest_rotation['z'])
            ), 'XYZ')
            cube.rotation_mode = 'QUATERNION'
            cube.rotation_quaternion = rotation.to_quaternion()

        return {'PASS_THROUGH'}

    def execute(self, context):
        self.receiver.start()
        wm = context.window_manager
        self._timer = wm.event_timer_add(1/OUTPUT_DATA_RATE, window=context.window)
        wm.modal_handler_add(self)
        return {'RUNNING_MODAL'}

    def cancel(self, context):
        self.receiver.running = False
        wm = context.window_manager
        wm.event_timer_remove(self._timer)

def register():
    bpy.utils.register_class(CubeRotationOperator)

def unregister():
    bpy.utils.unregister_class(CubeRotationOperator)

if __name__ == "__main__":
    register()
    bpy.ops.object.rotate_cube_from_socket()