from errno import EADDRINUSE
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import numpy as np
import socket
import json
import threading
import time

matplotlib.use('TkAgg')

class AccelerometerVisualizer:
    def __init__(self, port=65433):
        self.fig = plt.figure(figsize=(15, 7))
        self.ax1 = self.fig.add_subplot(121, projection='3d', elev=20, azim=30)
        self.ax2 = self.fig.add_subplot(122)

        self.latest_rotation = {'x': 0.0, 'y': 0.0, 'z': 0.0}
        self.running = True

        self.port = port
        self.thread = threading.Thread(target=self.receive_data)
        self.thread.daemon = True
        self.thread.start()

        self.anim = animation.FuncAnimation(
            self.fig,
            self.update_plot,
            interval=50,
            blit=False,
            cache_frame_data=False
        )

        self.setup_plots()

    def setup_plots(self):
        self.ax1.set_xlim([-10, 10])
        self.ax1.set_ylim([-10, 10])
        self.ax1.set_zlim([-10, 5])
        self.ax1.set_xlabel("X-Axis")
        self.ax1.set_ylabel("Y-Axis")
        self.ax1.set_zlabel("Z-Axis")
        self.ax1.set_title("Accelerometer Vectors")

        origin = np.array([0, 0, 0])
        self.vectors = {
            'gravity': self.ax1.quiver(*origin, 0, 0, -9.8, color='blue',
                                     label="Gravity Vector"),
            'x': self.ax1.quiver(*origin, 0, 0, 0, color='red',
                                label="X-Component"),
            'y': self.ax1.quiver(*origin, 0, 0, 0, color='green',
                                label="Y-Component"),
            'z': self.ax1.quiver(*origin, 0, 0, 0, color='orange',
                                label="Z-Component"),
            'resultant': self.ax1.quiver(*origin, 0, 0, 0, color='purple',
                                       label="Resultant")
        }
        self.ax1.legend()

        self.ax2.set_xlim([-1.5, 1.5])
        self.ax2.set_ylim([-1.5, 1.5])
        self.ax2.grid(True)
        self.ax2.set_aspect('equal')
        self.circle = plt.Circle((0, 0), 1, fill=False, color='gray')
        self.ax2.add_artist(self.circle)
        self.angle_arrow = self.ax2.arrow(0, 0, 0, 0, head_width=0.05,
                                        head_length=0.1, fc='purple', ec='purple')

    def receive_data(self):
        while self.running:
            try:
                conn, _ = self.sock.accept()
                print(f"Connected to data source")
                while self.running:
                    data = conn.recv(1024)
                    if not data:
                        break
                    try:
                        self.latest_rotation = json.loads(data.decode())
                    except json.JSONDecodeError:
                        print("Invalid JSON received")
            except socket.timeout:
                continue
            except ConnectionResetError:
                print("Connection was forcibly closed by the remote host")
            except ConnectionAbortedError:
                print("Connection was aborted by the software")
            except OSError as e:
                if e.errno == EADDRINUSE:
                    print("Port is already in use. Is another instance running?")
                    break
            except Exception as e:
                print(f"Error: {e}")
                time.sleep(1)

    def update_plot(self, _):
        pitch = np.radians(self.latest_rotation['x'])
        roll = np.radians(self.latest_rotation['y'])

        x_mag = 9.8 * np.sin(roll)
        y_mag = 9.8 * np.sin(pitch)
        z_mag = -9.8 * np.cos(pitch) * np.cos(roll)

        self.vectors['x'].set_segments([np.array([[0, 0, 0], [x_mag, 0, 0]])])
        self.vectors['y'].set_segments([np.array([[0, 0, 0], [0, y_mag, 0]])])
        self.vectors['z'].set_segments([np.array([[0, 0, 0], [0, 0, z_mag]])])

        resultant = np.array([x_mag, y_mag, z_mag])
        self.vectors['resultant'].set_segments([np.array([[0, 0, 0], resultant])])

        self.ax2.clear()
        self.ax2.set_xlim([-1.5, 1.5])
        self.ax2.set_ylim([-1.5, 1.5])
        self.ax2.grid(True)
        self.ax2.set_aspect('equal')
        self.ax2.add_artist(plt.Circle((0, 0), 1, fill=False, color='gray'))
        self.ax2.arrow(0, 0, np.sin(roll), np.sin(pitch),
                      head_width=0.05, head_length=0.1, fc='purple', ec='purple')
        self.ax2.set_title(f"Tilt Angles\nPitch: {np.degrees(pitch):.1f}°, "
                          f"Roll: {np.degrees(roll):.1f}°")

        return self.vectors.values()

    def setup_network(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.bind(('127.0.0.1', self.port))
        self.sock.listen(1)
        self.sock.settimeout(1.0)
        print(f"Listening on port {self.port}")

        self.thread = threading.Thread(target=self.receive_data)
        self.thread.daemon = True
        self.thread.start()

    def run(self):
        self.setup_network()
        plt.show()

if __name__ == "__main__":
    visualizer = AccelerometerVisualizer()
    visualizer.run()