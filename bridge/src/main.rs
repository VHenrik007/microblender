use clap::Parser;
use serde_json::Value;
use std::io::{self, Write};
use std::net::TcpStream;
use std::time::Duration;


struct ConnectionManager {
    blender: Option<TcpStream>,
    visualizer: Option<TcpStream>,
}

impl ConnectionManager {
    fn new(args: &Args) -> io::Result<Self> {
        let blender = if args.blender {
            Some(connect_to_service(&args.host, args.blender_port, "Blender")?)
        } else {
            None
        };

        let visualizer = if args.visualizer {
            Some(connect_to_service(&args.host, args.viz_port, "Visualizer")?)
        } else {
            None
        };

        Ok(Self { blender, visualizer })
    }

    fn forward_data(&mut self, data: &[u8]) -> io::Result<()> {
        if let Some(stream) = &mut self.blender {
            stream.write_all(data)?;
        }
        if let Some(stream) = &mut self.visualizer {
            stream.write_all(data)?;
        }
        Ok(())
    }
}

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    #[arg(long, default_value = "/dev/ttyACM0")]
    port: String,

    #[arg(long, default_value_t = 115200)]
    baud: u32,

    #[arg(long, default_value = "127.0.0.1")]
    host: String,

    #[arg(long)]
    blender: bool,

    #[arg(long)]
    visualizer: bool,

    #[arg(long, default_value_t = 65432)]
    blender_port: u16,

    #[arg(long, default_value_t = 65433)]
    viz_port: u16,
}

fn validate_configuration(args: &Args) -> Result<(), &'static str> {
    if args.blender && args.visualizer && args.blender_port == args.viz_port {
        return Err("Blender and Visualizer ports must be different");
    }
    if !args.blender && !args.visualizer {
        return Err("At least one of --blender or --visualizer must be specified");
    }
    Ok(())
}

fn setup_serial_port(args: &Args) -> serialport::Result<Box<dyn serialport::SerialPort>> {
    let port = serialport::new(&args.port, args.baud)
        .timeout(Duration::from_millis(10))
        .open()?;

    println!("Connected to Microbit on {}", args.port);
    Ok(port)
}

fn connect_to_service(host: &str, port: u16, service_name: &str) -> io::Result<TcpStream> {
    let addr = format!("{}:{}", host, port);
    println!("Attempting to connect to {} at {}", service_name, addr);

    loop {
        match TcpStream::connect(&addr) {
            Ok(stream) => {
                println!("Connected to {} at {}", service_name, addr);
                return Ok(stream);
            }
            Err(e) => {
                println!("Waiting for {}... ({})", service_name, e);
                std::thread::sleep(Duration::from_secs(3));
            }
        }
    }
}

fn process_json_line(line: &str, connections: &mut ConnectionManager) -> io::Result<()> {
    if let Ok(parsed) = serde_json::from_str::<Value>(line) {
        connections.forward_data(line.as_bytes())?;
        print!("Forwarded: {}\r", parsed);
        io::stdout().flush()?;
    } else {
        println!("Invalid JSON received: {}", line);
    }
    Ok(())
}

fn handle_serial_data(data: &[u8], message: &mut String) -> Option<String> {
    message.push_str(&String::from_utf8_lossy(data));

    if let Some(pos) = message.find('\n') {
        let line = message[..pos].trim().to_string();
        *message = message[pos + 1..].to_string();
        Some(line)
    } else {
        None
    }
}

fn run_data_processing(
    mut port: Box<dyn serialport::SerialPort>,
    mut connections: ConnectionManager,
) -> io::Result<()> {
    let mut serial_buf: Vec<u8> = vec![0; 1000];
    let mut message = String::new();

    println!("Starting data forwarding...");
    println!("Press Ctrl+C to exit");

    loop {
        match port.read(serial_buf.as_mut_slice()) {
            Ok(t) => {
                if let Some(line) = handle_serial_data(&serial_buf[..t], &mut message) {
                    process_json_line(&line, &mut connections)?;
                }
            }
            Err(ref e) if e.kind() == io::ErrorKind::TimedOut => (),
            Err(e) => {
                eprintln!("Error: {}", e);
                break;
            }
        }
    }
    Ok(())
}

fn main() -> io::Result<()> {
    let args = Args::parse();

    if let Err(e) = validate_configuration(&args) {
        eprintln!("Error: {}", e);
        return Ok(());
    }

    let port = setup_serial_port(&args)
        .expect("Failed to open serial port");

    let connections = ConnectionManager::new(&args)?;

    run_data_processing(port, connections)
}