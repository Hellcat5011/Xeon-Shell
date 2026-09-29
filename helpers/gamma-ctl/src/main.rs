use std::collections::HashMap;
use std::fs::File;
use std::io::{self, BufRead};
use std::os::unix::io::{AsFd, FromRawFd};
use std::sync::{Arc, Mutex};
use std::thread;
use serde::{Deserialize, Serialize};

use wayland_client::protocol::{wl_output, wl_registry};
use wayland_client::{Connection, Dispatch, EventQueue, Proxy, QueueHandle};
use wayland_protocols_wlr::gamma_control::v1::client::zwlr_gamma_control_manager_v1::ZwlrGammaControlManagerV1;
use wayland_protocols_wlr::gamma_control::v1::client::zwlr_gamma_control_v1::{ZwlrGammaControlV1, Event};
use std::sync::mpsc;
use std::time::{Duration, Instant};

#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type")]
enum Command {
    #[serde(rename = "set_temperature")]
    SetTemperature { kelvin: u32 },
    #[serde(rename = "get_status")]
    GetStatus,
}

#[derive(Serialize, Debug)]
pub struct OutputDetail {
    pub name: String,
    pub gamma_size: u32,
    pub failed: bool,
    pub applied_kelvin: Option<u32>,
}

#[derive(Serialize, Debug)]
#[serde(tag = "type")]
enum Response {
    #[serde(rename = "status")]
    Status {
        kelvin: u32,
        outputs: Vec<String>,
        failed_outputs: Vec<String>,
        details: Vec<OutputDetail>,
    },
    #[serde(rename = "error")]
    Error { message: String },
}

struct OutputState {
    name: Option<String>,
    output: wl_output::WlOutput,
    gamma_control: Option<ZwlrGammaControlV1>,
    gamma_size: u32,
    failed: bool,
    applied_kelvin: Option<u32>,
    last_attempt: Option<Instant>,
    first_failed_at: Option<Instant>,
}

struct AppState {
    outputs: HashMap<u32, OutputState>,
    gamma_manager: Option<ZwlrGammaControlManagerV1>,
    target_kelvin: u32,
    initialized: bool,
}

impl Dispatch<wl_registry::WlRegistry, ()> for AppState {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global { name, interface, version: _ } = event {
            if interface == "wl_output" {
                let output = registry.bind::<wl_output::WlOutput, _, _>(name, 4, qh, ());
                eprintln!("gamma-ctl: found wl_output id {name}");
                state.outputs.insert(name, OutputState {
                    name: None,
                    output,
                    gamma_control: None,
                    gamma_size: 0,
                    failed: false,
                    applied_kelvin: None,
                    last_attempt: None,
                    first_failed_at: None,
                });
            } else if interface == "zwlr_gamma_control_manager_v1" {
                eprintln!("gamma-ctl: bound zwlr_gamma_control_manager_v1 id {name}");
                let manager = registry.bind::<ZwlrGammaControlManagerV1, _, _>(name, 1, qh, ());
                state.gamma_manager = Some(manager);
            }
        }
    }
}

impl Dispatch<wl_output::WlOutput, ()> for AppState {
    fn event(
        state: &mut Self,
        output: &wl_output::WlOutput,
        event: wl_output::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        let _ = qh;
        if let wl_output::Event::Name { name } = event {
            eprintln!("gamma-ctl: wl_output name resolved to '{name}'");
            for (_, os) in state.outputs.iter_mut() {
                if &os.output == output {
                    os.name = Some(name.clone());
                    break;
                }
            }
        }
    }
}

impl Dispatch<ZwlrGammaControlManagerV1, ()> for AppState {
    fn event(_: &mut Self, _: &ZwlrGammaControlManagerV1, _: <ZwlrGammaControlManagerV1 as Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

impl Dispatch<ZwlrGammaControlV1, u32> for AppState {
    fn event(
        state: &mut Self,
        _gamma_control: &ZwlrGammaControlV1,
        event: Event,
        output_name: &u32,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match event {
            Event::GammaSize { size } => {
                let out_name = state.outputs.get(output_name).and_then(|o| o.name.clone()).unwrap_or_else(|| format!("id {output_name}"));
                if let Some(os) = state.outputs.get_mut(output_name) {
                    if os.failed {
                        let elapsed = os.first_failed_at.map(|t| Instant::now().duration_since(t).as_secs()).unwrap_or(0);
                        eprintln!("gamma-ctl: [Wayland event] gamma control successfully recovered for output '{out_name}'! (GammaSize: {size}, recovery took ~{elapsed}s)");
                    } else {
                        eprintln!("gamma-ctl: [Wayland event] output '{out_name}' received GammaSize: {size}");
                    }
                    os.gamma_size = size;
                    os.failed = false;
                    os.first_failed_at = None;
                    if state.initialized {
                        apply_gamma(os, state.target_kelvin);
                        os.applied_kelvin = Some(state.target_kelvin);
                    }
                }
            }
            Event::Failed => {
                let out_name = state.outputs.get(output_name).and_then(|o| o.name.clone()).unwrap_or_else(|| format!("id {output_name}"));
                eprintln!("gamma-ctl ERROR: [Wayland event] ZwlrGammaControlV1 failed for output '{out_name}'! (another client may already hold gamma control)");
                
                if let Some(os) = state.outputs.get_mut(output_name) {
                    os.failed = true;
                    os.gamma_size = 0;
                    if os.first_failed_at.is_none() {
                        os.first_failed_at = Some(Instant::now());
                    }
                    if let Some(control) = os.gamma_control.take() {
                        control.destroy();
                    }
                    os.last_attempt = Some(Instant::now());
                }
            }
            _ => {
                eprintln!("gamma-ctl: [Wayland event] output id {output_name} received unhandled event");
            }
        }
    }
}

fn color_temp_to_rgb(kelvin: f64) -> (f64, f64, f64) {
    let temp = kelvin / 100.0;
    let r = if temp <= 66.0 {
        255.0
    } else {
        let r = temp - 60.0;
        let r = 329.698727446 * r.powf(-0.1332047592);
        r.clamp(0.0, 255.0)
    };
    
    let g = if temp <= 66.0 {
        let g = temp;
        let g = 99.4708025861 * g.ln() - 161.1195681661;
        g.clamp(0.0, 255.0)
    } else {
        let g = temp - 60.0;
        let g = 288.1221695283 * g.powf(-0.0755148492);
        g.clamp(0.0, 255.0)
    };
    
    let b = if temp >= 66.0 {
        255.0
    } else if temp <= 19.0 {
        0.0
    } else {
        let b = temp - 10.0;
        let b = 138.5177312231 * b.ln() - 305.0447927307;
        b.clamp(0.0, 255.0)
    };
    
    (r / 255.0, g / 255.0, b / 255.0)
}

fn apply_gamma(os: &mut OutputState, kelvin: u32) {
    let name = os.name.as_deref().unwrap_or("<unnamed>");
    eprintln!("gamma-ctl: apply_gamma called for output '{name}', target_kelvin={kelvin}, gamma_size={}, has_control={}, failed={}",
        os.gamma_size, os.gamma_control.is_some(), os.failed);
    
    if os.failed {
        eprintln!("gamma-ctl: apply_gamma early return: output '{name}' marked as failed");
        return;
    }
    if os.gamma_size == 0 {
        eprintln!("gamma-ctl: apply_gamma early return: output '{name}' gamma_size is 0");
        return;
    }
    if os.gamma_control.is_none() {
        eprintln!("gamma-ctl: apply_gamma early return: output '{name}' has no gamma_control object");
        return;
    }
    
    let (r_mult, g_mult, b_mult) = color_temp_to_rgb(kelvin as f64);
    
    let size = os.gamma_size as usize;
    let bytes_len = size * 3 * 2;
    
    unsafe {
        let fd = libc::memfd_create("gamma\0".as_ptr() as *const libc::c_char, libc::MFD_CLOEXEC);
        if fd < 0 {
            eprintln!("gamma-ctl ERROR: memfd_create failed: {}", io::Error::last_os_error());
            return;
        }
        if libc::ftruncate(fd, bytes_len as libc::off_t) < 0 {
            eprintln!("gamma-ctl ERROR: ftruncate failed: {}", io::Error::last_os_error());
            libc::close(fd);
            return;
        }
        
        let ptr = libc::mmap(
            std::ptr::null_mut(),
            bytes_len,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_SHARED,
            fd,
            0,
        );
        if ptr == libc::MAP_FAILED {
            eprintln!("gamma-ctl ERROR: mmap failed: {}", io::Error::last_os_error());
            libc::close(fd);
            return;
        }
        
        let slice = std::slice::from_raw_parts_mut(ptr as *mut u16, size * 3);
        
        for i in 0..size {
            let val = i as f64 / (size - 1) as f64;
            slice[i] = (val * r_mult * u16::MAX as f64).round() as u16;
            slice[size + i] = (val * g_mult * u16::MAX as f64).round() as u16;
            slice[2 * size + i] = (val * b_mult * u16::MAX as f64).round() as u16;
        }
        
        libc::munmap(ptr, bytes_len);
        
        // Pass FD using FromRawFd to ensure it closes when dropped
        let file = File::from_raw_fd(fd);
        os.gamma_control.as_ref().unwrap().set_gamma(file.as_fd());
        eprintln!("gamma-ctl: set_gamma submitted successfully for output '{name}' ({kelvin}K, ramp size {size})");
    }
}

fn main() {
    eprintln!("gamma-ctl: starting (PID {})", std::process::id());
    eprintln!("gamma-ctl: initializing connection to Wayland...");
    let conn = Connection::connect_to_env().expect("Failed to connect to wayland");
    let display = conn.display();
    let mut event_queue: EventQueue<AppState> = conn.new_event_queue();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    
    let mut state = AppState {
        outputs: HashMap::new(),
        gamma_manager: None,
        target_kelvin: 6500,
        initialized: false,
    };
    
    event_queue.roundtrip(&mut state).unwrap();
    event_queue.roundtrip(&mut state).unwrap();
    
    if state.gamma_manager.is_none() {
        eprintln!("gamma-ctl ERROR: Compositor does not support wlr_gamma_control_unstable_v1");
        return;
    }
    
    // Bind all current outputs
    let manager = state.gamma_manager.as_ref().unwrap().clone();
    for (id, os) in state.outputs.iter_mut() {
        eprintln!("gamma-ctl: binding gamma control for output {:?}", os.name);
        let control = manager.get_gamma_control(&os.output, &qh, *id);
        os.gamma_control = Some(control);
        os.last_attempt = Some(Instant::now());
    }
    event_queue.roundtrip(&mut state).unwrap();

    let state_arc = Arc::new(Mutex::new(state));
    let state_clone = state_arc.clone();
    
    let (tx, rx) = mpsc::channel();
    
    thread::spawn(move || {
        let stdin = io::stdin();
        let mut handle = stdin.lock();
        let mut line = String::new();
        while handle.read_line(&mut line).unwrap_or(0) > 0 {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                line.clear();
                continue;
            }
            eprintln!("gamma-ctl: [stdin] received line: {trimmed}");
            if let Ok(cmd) = serde_json::from_str::<Command>(trimmed) {
                eprintln!("gamma-ctl: [stdin] parsed command: {cmd:?}");
                let mut st = state_clone.lock().unwrap();
                match cmd {
                    Command::SetTemperature { kelvin } => {
                        st.target_kelvin = kelvin;
                        st.initialized = true;
                        let _ = tx.send(()); // wake up main thread
                    }
                    Command::GetStatus => {
                        let mut outs = Vec::new();
                        let mut failed_outs = Vec::new();
                        let mut details = Vec::new();
                        for os in st.outputs.values() {
                            let name = os.name.clone().unwrap_or_else(|| "unknown".into());
                            if os.failed {
                                failed_outs.push(name.clone());
                            } else {
                                outs.push(name.clone());
                            }
                            details.push(OutputDetail {
                                name,
                                gamma_size: os.gamma_size,
                                failed: os.failed,
                                applied_kelvin: os.applied_kelvin,
                            });
                        }
                        let resp = Response::Status {
                            kelvin: st.target_kelvin,
                            outputs: outs,
                            failed_outputs: failed_outs,
                            details,
                        };
                        println!("{}", serde_json::to_string(&resp).unwrap());
                    }
                }
            } else {
                eprintln!("gamma-ctl ERROR: [stdin] invalid command: {trimmed}");
                let err = Response::Error { message: format!("Invalid command: {trimmed}") };
                println!("{}", serde_json::to_string(&err).unwrap());
            }
            line.clear();
        }
        eprintln!("gamma-ctl: stdin reached EOF, reader thread exiting.");
    });

    loop {
        if let Some(guard) = event_queue.prepare_read() {
            let _ = guard.read();
        }
        let _ = event_queue.dispatch_pending(&mut *state_arc.lock().unwrap());

        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(()) => {},
            Err(mpsc::RecvTimeoutError::Timeout) => {},
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                eprintln!("gamma-ctl: stdin disconnected, exiting.");
                break;
            }
        }

        // Manage gamma controls and apply gamma
        let mut st = state_arc.lock().unwrap();
        if let Some(manager) = st.gamma_manager.clone() {
            let target_kelvin = st.target_kelvin;
            let initialized = st.initialized;
            let now = Instant::now();

            for (id, os) in st.outputs.iter_mut() {
                if os.gamma_control.is_none() {
                    // Determine retry interval: 1s for first 15s after initial failure (fast phase),
                    // then 5s thereafter (slow phase). This handles transient startup conditions
                    // where the compositor may not be ready to grant gamma control yet.
                    let secs_since_first_fail = os.first_failed_at
                        .map(|t| now.duration_since(t).as_secs())
                        .unwrap_or(0);
                    let (retry_interval, phase) = if secs_since_first_fail <= 15 {
                        (Duration::from_secs(1), "fast")
                    } else {
                        (Duration::from_secs(5), "slow")
                    };

                    let should_retry = match os.last_attempt {
                        Some(last) => now.duration_since(last) >= retry_interval,
                        None => true,
                    };
                    if should_retry {
                        let out_name = os.name.as_deref().unwrap_or("<unnamed>");
                        eprintln!("gamma-ctl: retrying gamma control bind for output '{out_name}' ({phase} phase, {secs_since_first_fail}s since first failure)...");
                        os.last_attempt = Some(now);
                        let control = manager.get_gamma_control(&os.output, &qh, *id);
                        os.gamma_control = Some(control);
                    }
                } else if os.gamma_size > 0 && !os.failed && initialized {
                    if os.applied_kelvin != Some(target_kelvin) {
                        apply_gamma(os, target_kelvin);
                        os.applied_kelvin = Some(target_kelvin);
                    }
                }
            }
        }
        drop(st);

        // Crucial flush: immediately push set_gamma requests to the compositor
        if let Err(e) = conn.flush() {
            eprintln!("gamma-ctl ERROR: conn.flush failed: {e}");
        }
    }

    let mut st = state_arc.lock().unwrap();
    for os in st.outputs.values_mut() {
        if let Some(control) = os.gamma_control.take() {
            eprintln!("gamma-ctl: destroying gamma control for output {:?}", os.name);
            control.destroy();
        }
    }
    let _ = conn.flush();
    eprintln!("gamma-ctl: shutdown complete.");
}


