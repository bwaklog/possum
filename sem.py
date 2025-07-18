import serial
import struct
import sys
import time
import threading

def serial_logger(ser, stop_event):
    while not stop_event.is_set():
        if ser.in_waiting:
            try:
                data = ser.read(ser.in_waiting)
                print(data.decode(errors="replace"), end="")
            except Exception:
                pass
        time.sleep(0.01)

def send_program_uart(port, baudrate, file_path):
    ser = serial.Serial(port, baudrate, timeout=1)
    time.sleep(2)  

    stop_event = threading.Event()
    logger_thread = threading.Thread(target=serial_logger, args=(ser, stop_event))
    logger_thread.start()

    print("[INFO] Logging serial output for 2 seconds...")
    time.sleep(2)

    print("[INFO] Sending LOADPROG keyword...")
    ser.write(b'LOADPROG')
    time.sleep(0.05)

    with open(file_path, "rb") as f:
        data = f.read()

    print(f"[INFO] Sending program size: {len(data)} bytes...")
    size_bytes = struct.pack('<Q', len(data))
    ser.write(size_bytes)
    time.sleep(0.05)

    print("[INFO] Sending program data...")
    ser.write(data)
    print(f"[INFO] Sent {len(data)} bytes.")

    print("[INFO] Logging serial output for 2 more seconds...")
    time.sleep(2)

    stop_event.set()
    logger_thread.join()
    ser.close()

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python send_program_uart.py <COM_PORT> <BAUDRATE> <FILE_PATH>")
        sys.exit(1)
    send_program_uart(sys.argv[1], int(sys.argv[2]), sys.argv[3])