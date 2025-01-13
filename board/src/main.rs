#![no_main] // Don't use the Rust standard entry point
#![no_std] // Don't link the Rust standard library

use cortex_m_rt::entry;  // Provides our new entry point
use micromath::F32Ext;   // Math operations for f32 without std
use panic_rtt_target as _;  // Handles program crashes
use rtt_target::rtt_init_print;  // Allows debug printing

use microbit::{
    hal::twim,
    hal::uarte,
    hal::uarte::{Baudrate, Parity},
    pac::twim0::frequency::FREQUENCY_A,
};

mod serial_setup;
use serial_setup::UartePort;

use core::{f32::EPSILON, fmt::Write};
use lsm303agr::{AccelOutputDataRate, Lsm303agr};

fn calculate_rotation(x: i32, y: i32, z: i32) -> (f32, f32) {
    // Convert raw accelerometer data to g force (assuming ±2g range)
    let x_g = (x as f32) / 16384.0;
    let y_g = (y as f32) / 16384.0;
    let z_g = (z as f32) / 16384.0;

    let pitch = (y_g / ((x_g * x_g + z_g * z_g).sqrt() + EPSILON)).atan();
    let roll = (x_g / ((y_g * y_g + z_g * z_g).sqrt() + EPSILON)).atan();

    let pitch_deg = pitch * 57.295779513; // 180/pi
    let roll_deg = roll * 57.295779513; // 180/pi

    (pitch_deg, roll_deg)
}

#[entry]
fn main() -> ! {
    rtt_init_print!();
    let board = microbit::Board::take().unwrap();

    let mut serial = {
        let serial = uarte::Uarte::new(
            board.UARTE0,
            board.uart.into(),
            Parity::EXCLUDED,
            Baudrate::BAUD115200,
        );
        UartePort::new(serial)
    };

    let i2c = { twim::Twim::new(board.TWIM0, board.i2c_internal.into(), FREQUENCY_A::K100) };

    let mut sensor = Lsm303agr::new_with_i2c(i2c);
    sensor.init().unwrap();
    sensor.set_accel_odr(AccelOutputDataRate::Hz50).unwrap();

    let mut sensor = sensor.into_mag_continuous().ok().unwrap();

    loop {
        // Wait until accelerometer data is ready
        while !sensor.accel_status().unwrap().xyz_new_data {}

        let accel_data = sensor.accel_data().unwrap();
        let (pitch, roll) = calculate_rotation(accel_data.x, accel_data.y, accel_data.z);

        write!(
            serial,
            "{{\"x\":{:.1},\"y\":{:.1},\"z\":0.0}}\r\n",
            pitch, roll
        )
        .unwrap();
    }
}
