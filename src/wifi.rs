use serde::Serialize;
use std::sync::Arc;
use tokio::process::Command;
use tokio::sync::RwLock;
use tracing::{info, warn};

/// Default hotspot SSID.
pub const HOTSPOT_SSID: &str = "Noisey-Setup";
/// Default hotspot WPA2 password.
pub const HOTSPOT_PASSWORD: &str = "noisey42";
/// Default WiFi interface.
const IFACE: &str = "wlan0";

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum WifiState {
    /// Checking network status on boot.
    Unknown,
    /// Broadcasting AP, waiting for user to configure.
    AccessPoint,
    /// Attempting to connect to user's WiFi.
    Connecting { ssid: String },
    /// Successfully connected to a network.
    Connected { ip: String },
    /// Connection attempt failed.
    Failed { reason: String },
}

#[derive(Debug, Clone, Serialize)]
pub struct WifiNetwork {
    pub ssid: String,
    pub signal: u8,
    pub security: String,
}

pub type SharedWifiState = Arc<RwLock<WifiState>>;

/// Check if the device has internet connectivity via NetworkManager.
pub async fn check_connectivity() -> bool {
    let output = Command::new("nmcli")
        .args(["networking", "connectivity", "check"])
        .output()
        .await;

    match output {
        Ok(o) => {
            let stdout = String::from_utf8_lossy(&o.stdout);
            let result = stdout.trim();
            // "full" means internet access, "limited" means local only
            result == "full"
        }
        Err(e) => {
            warn!("WiFi: failed to check connectivity: {e}");
            false
        }
    }
}

/// Scan for available WiFi networks.
pub async fn scan_networks() -> Vec<WifiNetwork> {
    let output = Command::new("nmcli")
        .args([
            "-t",
            "-f",
            "SSID,SIGNAL,SECURITY",
            "dev",
            "wifi",
            "list",
            "--rescan",
            "yes",
        ])
        .output()
        .await;

    match output {
        Ok(o) => parse_scan_output(&String::from_utf8_lossy(&o.stdout)),
        Err(e) => {
            warn!("WiFi: scan failed: {e}");
            Vec::new()
        }
    }
}

/// Parse nmcli terse WiFi scan output into structured data.
pub fn parse_scan_output(output: &str) -> Vec<WifiNetwork> {
    let mut networks = Vec::new();
    let mut seen = std::collections::HashSet::new();

    for line in output.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        // nmcli -t uses ':' as separator but escapes colons in values as '\:'.
        // Split respecting escaped colons: collect fields by splitting on
        // unescaped ':'.
        let fields = split_nmcli_line(line);
        if fields.len() < 3 {
            continue;
        }

        let ssid = &fields[0];
        if ssid.is_empty() {
            continue;
        }

        // Deduplicate by SSID (multiple APs for same network)
        if !seen.insert(ssid.clone()) {
            continue;
        }

        let signal: u8 = fields[1].parse().unwrap_or(0);
        let security = fields[2].clone();

        networks.push(WifiNetwork {
            ssid: ssid.clone(),
            signal,
            security,
        });
    }

    // Sort by signal strength descending
    networks.sort_by(|a, b| b.signal.cmp(&a.signal));
    networks
}

/// Split an nmcli terse-mode line on unescaped ':' delimiters.
/// Backslash-colon sequences (\:) are treated as literal colons in the value.
fn split_nmcli_line(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut chars = line.chars().peekable();

    while let Some(c) = chars.next() {
        if c == '\\' {
            if let Some(&next) = chars.peek() {
                if next == ':' {
                    current.push(':');
                    chars.next();
                    continue;
                }
            }
            current.push(c);
        } else if c == ':' {
            fields.push(std::mem::take(&mut current));
        } else {
            current.push(c);
        }
    }
    fields.push(current);
    fields
}

/// Start a WiFi hotspot for setup mode.
pub async fn start_hotspot() -> Result<(), String> {
    info!(
        ssid = HOTSPOT_SSID,
        password = HOTSPOT_PASSWORD,
        "WiFi: starting setup hotspot"
    );

    let output = Command::new("nmcli")
        .args([
            "dev",
            "wifi",
            "hotspot",
            "ifname",
            IFACE,
            "ssid",
            HOTSPOT_SSID,
            "password",
            HOTSPOT_PASSWORD,
        ])
        .output()
        .await
        .map_err(|e| format!("failed to run nmcli: {e}"))?;

    if output.status.success() {
        info!("WiFi: hotspot started on {IFACE}");
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("nmcli hotspot failed: {stderr}"))
    }
}

/// Stop the hotspot connection.
pub async fn stop_hotspot() -> Result<(), String> {
    let output = Command::new("nmcli")
        .args(["connection", "down", "Hotspot"])
        .output()
        .await
        .map_err(|e| format!("failed to run nmcli: {e}"))?;

    if output.status.success() {
        info!("WiFi: hotspot stopped");
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("nmcli stop hotspot failed: {stderr}"))
    }
}

/// Connect to a WiFi network with the given SSID and password.
pub async fn connect(ssid: &str, password: &str) -> Result<(), String> {
    info!(ssid = %ssid, "WiFi: attempting connection");

    let output = Command::new("nmcli")
        .args([
            "dev", "wifi", "connect", ssid, "password", password, "ifname", IFACE,
        ])
        .output()
        .await
        .map_err(|e| format!("failed to run nmcli: {e}"))?;

    if output.status.success() {
        info!(ssid = %ssid, "WiFi: connected successfully");
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        let msg = if stderr.is_empty() {
            stdout.trim().to_string()
        } else {
            stderr.trim().to_string()
        };
        Err(format!("connection failed: {msg}"))
    }
}

/// Get the current IP address of the WiFi interface.
pub async fn get_device_ip() -> Option<String> {
    let output = Command::new("nmcli")
        .args(["-t", "-f", "IP4.ADDRESS", "dev", "show", IFACE])
        .output()
        .await
        .ok()?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    parse_ip_output(&stdout)
}

/// Parse nmcli device IP output.
pub fn parse_ip_output(output: &str) -> Option<String> {
    for line in output.lines() {
        let line = line.trim();
        // Format: IP4.ADDRESS[1]:192.168.1.100/24
        if let Some(addr) = line.strip_prefix("IP4.ADDRESS") {
            // Strip the [N]: prefix
            if let Some(ip_cidr) = addr.split(':').nth(1) {
                // Remove CIDR suffix (/24)
                let ip = ip_cidr.split('/').next().unwrap_or(ip_cidr);
                if !ip.is_empty() {
                    return Some(ip.to_string());
                }
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_scan_output() {
        let output = "MyNetwork:85:WPA2\nGuest:42:--\nMyNetwork:70:WPA2\n:30:WPA2\n";
        let networks = parse_scan_output(output);

        assert_eq!(networks.len(), 2);
        assert_eq!(networks[0].ssid, "MyNetwork");
        assert_eq!(networks[0].signal, 85);
        assert_eq!(networks[0].security, "WPA2");
        assert_eq!(networks[1].ssid, "Guest");
        assert_eq!(networks[1].signal, 42);
        assert_eq!(networks[1].security, "--");
    }

    #[test]
    fn test_parse_scan_output_escaped_colon() {
        let output = "My\\:Network:90:WPA2\n";
        let networks = parse_scan_output(output);

        assert_eq!(networks.len(), 1);
        assert_eq!(networks[0].ssid, "My:Network");
    }

    #[test]
    fn test_parse_scan_output_empty() {
        let networks = parse_scan_output("");
        assert!(networks.is_empty());
    }

    #[test]
    fn test_parse_ip_output() {
        let output = "IP4.ADDRESS[1]:192.168.1.100/24\n";
        assert_eq!(parse_ip_output(output), Some("192.168.1.100".to_string()));
    }

    #[test]
    fn test_parse_ip_output_none() {
        let output = "IP6.ADDRESS[1]:fe80::1/64\n";
        assert_eq!(parse_ip_output(output), None);
    }

    #[test]
    fn test_parse_ip_output_empty() {
        assert_eq!(parse_ip_output(""), None);
    }
}
