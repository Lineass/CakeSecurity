import ble_sensor
import bluetooth
from machine import Pin, I2C, UART
import time
import vl53l0x

# UART pour recevoir les ordres de la F746
uart = UART(2, baudrate=115200)

# Buzzer
buzzer = Pin('D4', Pin.OUT)

# TOF
i2c = I2C(1)
tof = vl53l0x.VL53L0X(i2c)

# BLE
ble = bluetooth.BLE()
ble_device = ble_sensor.BLESensor(ble)
print("BLE démarré !")

# Distance de référence
time.sleep(1)
distance_ref = tof.read()
print("Distance de référence :", distance_ref, "mm")

SEUIL = 20  # 2cm
actif = False
vol_detecte = False

while True:
    # Vérifie si on reçoit un ordre UART depuis la F746
    if uart.any():
        msg = uart.read(1)
        if msg == b'1':
            actif = True
            print("Surveillance ON")
        elif msg == b'0':
            actif = False
            #buzzer.value(0)
            print("Surveillance OFF")

    # Surveillance TOF si actif
    if actif:
        distance = tof.read()
        print(distance, "mm")

        if abs(distance - distance_ref) > SEUIL:
            if not vol_detecte:
                vol_detecte = True
                print("VOL DETECTE !")
                ble_device.set_data_temperature(99, notify=1)

            #buzzer.value(1)
            time.sleep(0.2)
            #buzzer.value(0)
            time.sleep(0.2)
        else:
            #buzzer.value(0)
            vol_detecte = False
    
    time.sleep(0.1)