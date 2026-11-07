#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde_json::{json, Map, Value};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, WebviewWindow};

const HOST: &str = "10.168.1.1";
const KEYRING_SERVICE: &str = "com.xuyaoshi.pgymenu";
const KEYRING_USER: &str = "admin";

const POLL_CMDS: &[&str] = &[
    "signalbar",
    "network_type",
    "sub_network_type",
    "network_provider",
    "ppp_status",
    "lte_rsrp",
    "nv_rsrq",
    "nv_sinr",
    "nv_band",
    "nv_arfcn",
    "nv_pci",
    "nv_cellid",
    "realtime_rx_bytes",
    "realtime_tx_bytes",
    "realtime_time",
    "monthly_rx_bytes",
    "monthly_tx_bytes",
    "monthly_time",
    "wifi_cur_state",
    "SSID1",
    "upnpEnabled",
    "DMZEnable",
    "DMZIPAddress",
    "lan_ipaddr",
    "lan_netmask",
    "dhcpEnabled",
    "dhcpStart",
    "dhcpEnd",
    "dhcpLease_hour",
    "sim_esim_mode",
    "user_web_disp_sim_esim_config",
    "imei",
    "msisdn",
    "ziccid",
    "cr_version",
    "hw_version",
    "web_version",
    "run_time",
];

#[derive(Clone)]
struct Shared {
    status: Arc<Mutex<Value>>,
    password: Arc<Mutex<String>>,
}

impl Shared {
    fn new() -> Self {
        Self {
            status: Arc::new(Mutex::new(json!({}))),
            password: Arc::new(Mutex::new(load_admin_password())),
        }
    }

    fn password(&self) -> String {
        self.password
            .lock()
            .map(|p| p.clone())
            .unwrap_or_else(|_| "admin".to_string())
    }

    fn set_password(&self, password: &str) {
        if let Ok(mut stored) = self.password.lock() {
            *stored = password.to_string();
        }
    }
}

fn load_admin_password() -> String {
    keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER)
        .ok()
        .and_then(|entry| entry.get_password().ok())
        .unwrap_or_else(|| "admin".to_string())
}

fn save_admin_password(password: &str) -> Result<(), String> {
    let entry = keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER).map_err(|e| e.to_string())?;
    entry.set_password(password).map_err(|e| e.to_string())
}

fn client() -> reqwest::blocking::Client {
    reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(4))
        .build()
        .expect("http client")
}

fn api_get(client: &reqwest::blocking::Client, cmds: &[&str]) -> Option<Map<String, Value>> {
    let url = format!(
        "http://{}/goform/goform_get_cmd_process?isTest=false&multi_data=1&cmd={}",
        HOST,
        cmds.join(",")
    );
    let resp = client
        .get(&url)
        .header("Referer", format!("http://{}/index.html", HOST))
        .send()
        .ok()?;
    let value: Value = resp.json().ok()?;
    value.as_object().cloned()
}

fn api_post(
    client: &reqwest::blocking::Client,
    form: &[(&str, String)],
) -> Option<Map<String, Value>> {
    let url = format!("http://{}/goform/goform_set_cmd_process", HOST);
    let mut params: Vec<(String, String)> = vec![("isTest".into(), "false".into())];
    for (k, v) in form {
        params.push(((*k).to_string(), v.clone()));
    }
    let resp = client
        .post(&url)
        .header("Referer", format!("http://{}/index.html", HOST))
        .form(&params)
        .send()
        .ok()?;
    let value: Value = resp.json().ok()?;
    value.as_object().cloned()
}

fn login(client: &reqwest::blocking::Client, password: &str) -> bool {
    let user = base64("admin");
    let pass = base64(password);
    match api_post(
        client,
        &[
            ("goformId", "LOGIN".into()),
            ("username", user),
            ("password", pass),
        ],
    ) {
        Some(obj) => obj.get("result").and_then(|v| v.as_str()) == Some("0"),
        None => false,
    }
}

fn base64(text: &str) -> String {
    use base64_encoder::encode;
    encode(text.as_bytes())
}

/// 极简 base64（避免为一个函数引入额外 crate）
mod base64_encoder {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    pub fn encode(input: &[u8]) -> String {
        let mut out = String::with_capacity(input.len().div_ceil(3) * 4);
        for chunk in input.chunks(3) {
            let b = [
                chunk[0],
                *chunk.get(1).unwrap_or(&0),
                *chunk.get(2).unwrap_or(&0),
            ];
            let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
            out.push(TABLE[(n >> 18) as usize & 63] as char);
            out.push(TABLE[(n >> 12) as usize & 63] as char);
            out.push(if chunk.len() > 1 {
                TABLE[(n >> 6) as usize & 63] as char
            } else {
                '='
            });
            out.push(if chunk.len() > 2 {
                TABLE[n as usize & 63] as char
            } else {
                '='
            });
        }
        out
    }
}

fn do_set(_label: &str, form: &[(&str, String)]) -> bool {
    let client = client();
    match api_post(&client, form) {
        Some(obj) => obj
            .get("result")
            .and_then(|v| v.as_str())
            .map(|r| r == "success" || r == "0")
            .unwrap_or(false),
        None => false,
    }
}

fn set_result(app: &AppHandle, label: &str, ok: bool) {
    if ok {
        let _ = app.emit(
            "toast",
            json!({ "message": format!("{}成功", label), "error": false }),
        );
    } else {
        let _ = app.emit(
            "toast",
            json!({ "message": format!("{}失败", label), "error": true }),
        );
    }
}

fn take_number(obj: &Map<String, Value>, key: &str) -> i64 {
    match obj.get(key) {
        Some(Value::Number(n)) => n.as_i64().unwrap_or(0),
        Some(Value::String(s)) => s.parse::<i64>().unwrap_or(0),
        _ => 0,
    }
}

fn take_string(obj: &Map<String, Value>, key: &str) -> String {
    match obj.get(key) {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        _ => String::new(),
    }
}

/// 生成菜单栏信号图标（RGBA，模板图）
fn draw_icon(bars: i64, connected: bool) -> tauri::image::Image<'static> {
    const W: u32 = 44;
    const H: u32 = 24;
    let mut data = vec![0u8; (W * H * 4) as usize];
    let count = bars.clamp(0, 5) as f64;
    let heights = [0.26f64, 0.45, 0.64, 0.82, 1.0];
    let bar_w = 5.0;
    let gap = 2.0;
    let total = bar_w * 5.0 + gap * 4.0;
    let x0 = (W as f64 - total) / 2.0;
    let max_h = H as f64 * 0.86;
    let base = (H as f64 - max_h) / 2.0;

    for (i, height) in heights.iter().enumerate() {
        let h = max_h * height;
        let x = x0 + i as f64 * (bar_w + gap);
        let y = base + (max_h - h);
        let on = (i as f64) < count;
        let alpha: u8 = if on {
            if connected {
                255
            } else {
                160
            }
        } else {
            70
        };
        let x_start = x.round() as u32;
        let x_end = (x + bar_w).round() as u32;
        let y_start = y.round() as u32;
        let y_end = (y + h).round() as u32;
        for py in y_start..y_end.min(H) {
            for px in x_start..x_end.min(W) {
                let idx = ((py * W + px) * 4) as usize;
                data[idx] = 0;
                data[idx + 1] = 0;
                data[idx + 2] = 0;
                data[idx + 3] = alpha;
            }
        }
    }
    tauri::image::Image::new_owned(data, W, H)
}

fn update_tray(app: &AppHandle, bars: i64, connected: bool, tooltip: &str) {
    if let Some(tray) = app.tray_by_id("main") {
        let _ = tray.set_icon(Some(draw_icon(bars, connected)));
        let _ = tray.set_tooltip(Some(tooltip));
    }
}

fn spawn_poller(app: AppHandle, shared: Shared) {
    thread::spawn(move || {
        let client = client();
        let mut logged_in = login(&client, &shared.password());
        let mut login_fail_notified = false;
        let mut last_rx: i64 = -1;
        let mut last_tx: i64 = -1;
        let mut last_sample = Instant::now();
        loop {
            if !logged_in {
                logged_in = login(&client, &shared.password());
                if !logged_in && !login_fail_notified {
                    let _ = app.emit("toast", json!({
                        "message": "设备登录失败：管理密码可能不对，请在 设置 → 设备 修改登录密码",
                        "error": true
                    }));
                    login_fail_notified = true;
                }
                if logged_in {
                    login_fail_notified = false;
                }
            }
            if let Some(mut obj) = api_get(&client, POLL_CMDS) {
                let rx = take_number(&obj, "realtime_rx_bytes");
                let tx = take_number(&obj, "realtime_tx_bytes");
                let now = Instant::now();
                let dt = now.duration_since(last_sample).as_secs_f64();
                let mut rx_speed = 0i64;
                let mut tx_speed = 0i64;
                if last_rx >= 0 && dt > 0.2 {
                    rx_speed = ((rx - last_rx) as f64 / dt).max(0.0) as i64;
                    tx_speed = ((tx - last_tx) as f64 / dt).max(0.0) as i64;
                }
                last_rx = rx;
                last_tx = tx;
                last_sample = now;

                obj.insert("rx_speed".into(), json!(rx_speed));
                obj.insert("tx_speed".into(), json!(tx_speed));
                let logged = take_string(&obj, "loginfo") == "ok" || logged_in;
                obj.insert("logged_in".into(), json!(logged));

                let value = Value::Object(obj.clone());
                if let Ok(mut guard) = shared.status.lock() {
                    *guard = value.clone();
                }
                let _ = app.emit("status", value);

                let bars = take_number(&obj, "signalbar");
                let ppp = take_string(&obj, "ppp_status");
                let provider = take_string(&obj, "network_provider");
                let rsrp = take_string(&obj, "lte_rsrp");
                let connected = ppp == "ppp_connected";
                let tooltip = if provider.is_empty() {
                    "PGY 随身 WiFi".to_string()
                } else {
                    format!(
                        "PGY 随身 WiFi · {} · {} dBm",
                        provider,
                        if rsrp.is_empty() { "--" } else { &rsrp }
                    )
                };
                update_tray(&app, bars, connected, &tooltip);
                if take_string(&obj, "loginfo") != "ok" {
                    logged_in = login(&client, &shared.password());
                }
            } else {
                if let Ok(mut guard) = shared.status.lock() {
                    *guard = json!({ "offline": true });
                    let _ = app.emit("status", guard.clone());
                    update_tray(&app, 0, false, "PGY 随身 WiFi · 未连接设备");
                }
            }
            thread::sleep(Duration::from_secs(2));
        }
    });
}

fn toggle_panel(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("panel") {
        let visible = win.is_visible().unwrap_or(false);
        if visible {
            let _ = win.hide();
        } else {
            position_panel(&win);
            let _ = win.show();
            let _ = win.set_focus();
        }
    }
}

fn position_panel(win: &WebviewWindow) {
    if let Ok(Some(monitor)) = win.current_monitor() {
        let size = monitor.size();
        let scale = monitor.scale_factor();
        if let Ok(win_size) = win.outer_size() {
            let x = size.width as f64 - win_size.width as f64 - 14.0 * scale;
            let _ = win.set_position(tauri::PhysicalPosition::new(
                x.max(0.0) as i32,
                (30.0 * scale) as i32,
            ));
        }
    }
}

#[tauri::command]
fn get_status(shared: tauri::State<Shared>) -> Value {
    shared.status.lock().map(|g| g.clone()).unwrap_or(json!({}))
}

#[tauri::command]
fn set_admin_password(
    app: AppHandle,
    shared: tauri::State<Shared>,
    password: String,
) -> Result<bool, String> {
    save_admin_password(&password)?;
    shared.set_password(&password);
    let ok = login(&client(), &password);
    let _ = app.emit(
        "toast",
        json!({
            "message": if ok { "登录密码已保存，登录成功" } else { "密码已保存，但登录失败，请检查" },
            "error": !ok
        }),
    );
    Ok(ok)
}

#[tauri::command]
fn change_admin_password(
    shared: tauri::State<Shared>,
    old: String,
    new: String,
) -> Result<bool, String> {
    let client = client();
    if !login(&client, &old) {
        return Err("旧密码登录失败".into());
    }
    let ok = api_post(
        &client,
        &[
            ("goformId", "CHANGE_PASSWORD".into()),
            ("oldPassword", base64(&old)),
            ("newPassword", base64(&new)),
        ],
    )
    .map(|obj| obj.get("result").and_then(|v| v.as_str()) == Some("success"))
    .unwrap_or(false);
    if ok {
        save_admin_password(&new)?;
        shared.set_password(&new);
    }
    Ok(ok)
}

#[tauri::command]
fn get_apns() -> Result<Value, String> {
    let client = client();
    let mut cmds: Vec<String> = vec![
        "apn_mode".into(),
        "m_profile_name".into(),
        "wan_apn".into(),
        "pdp_type".into(),
    ];
    for i in 0..20 {
        cmds.push(format!("APN_config{i}"));
    }
    let refs: Vec<&str> = cmds.iter().map(|s| s.as_str()).collect();
    let obj = api_get(&client, &refs).ok_or("无法读取 APN（设备可能未连接）")?;
    let current = take_string(&obj, "m_profile_name");
    let mut list = Vec::new();
    for i in 0..20 {
        let raw = take_string(&obj, &format!("APN_config{i}"));
        if raw.is_empty() {
            continue;
        }
        let parts: Vec<&str> = raw.split("($)").collect();
        if parts.len() < 7 {
            continue;
        }
        let name = parts.get(2).unwrap_or(&"").to_string();
        let apn = parts.get(3).unwrap_or(&"").to_string();
        let mode = parts.get(4).unwrap_or(&"").to_string();
        let auth = parts.get(6).unwrap_or(&"").to_string();
        let pdp = parts.get(9).unwrap_or(&"IPv4").to_string();
        list.push(json!({
            "index": i,
            "profileName": name,
            "apn": apn,
            "mode": mode,
            "auth": auth,
            "pdpType": pdp,
            "current": !current.is_empty() && name == current,
        }));
    }
    Ok(json!(list))
}

#[tauri::command]
fn set_default_apn(app: AppHandle, index: u32, pdp_type: String) -> Result<bool, String> {
    let client = client();
    let ok = api_post(
        &client,
        &[
            ("goformId", "APN_PROC_EX".into()),
            ("apn_mode", "manual".into()),
            ("apn_action", "set_default".into()),
            ("set_default_flag", "1".into()),
            ("pdp_type", pdp_type),
            ("index", index.to_string()),
        ],
    )
    .map(|obj| obj.get("result").and_then(|v| v.as_str()) == Some("success"))
    .unwrap_or(false);
    let _ = app.emit(
        "toast",
        json!({ "message": if ok { "APN 已切换" } else { "APN 切换失败" }, "error": !ok }),
    );
    Ok(ok)
}

#[tauri::command]
fn open_settings(app: AppHandle) {
    if let Some(win) = app.get_webview_window("settings") {
        let _ = win.show();
        let _ = win.set_focus();
        let _ = win.set_position(tauri::LogicalPosition::new(180.0, 120.0));
    }
    if let Some(panel) = app.get_webview_window("panel") {
        let _ = panel.hide();
    }
}

#[tauri::command]
fn hide_panel(app: AppHandle) {
    if let Some(win) = app.get_webview_window("panel") {
        let _ = win.hide();
    }
}

#[tauri::command]
fn quit_app(app: AppHandle) {
    app.exit(0);
}

#[tauri::command]
fn set_wifi(app: AppHandle, on: bool) {
    let ok = do_set(
        "设置 WiFi",
        &[
            ("goformId", "SET_WIFI_INFO".into()),
            ("wifiEnabled", if on { "1" } else { "0" }.into()),
            ("m_ssid_enable", if on { "1" } else { "0" }.into()),
        ],
    );
    set_result(&app, if on { "开启 WiFi" } else { "关闭 WiFi" }, ok);
}

#[tauri::command]
fn save_wifi(app: AppHandle, ssid: String, password: String, hidden: bool) {
    let key = base64(&password);
    let ok = do_set(
        "保存 WiFi 设置",
        &[
            ("goformId", "SET_WIFI_SSID1_SETTINGS".into()),
            ("ssid", ssid),
            (
                "broadcastSsidEnabled",
                if hidden { "0" } else { "1" }.into(),
            ),
            ("MAX_Access_num", "8".into()),
            ("security_mode", "WPAPSKWPA2PSK".into()),
            ("cipher", "TKIPAES".into()),
            ("security_shared_mode", "TKIPAES".into()),
            ("NoForwarding", "0".into()),
            ("show_qrcode_flag", "1".into()),
            ("passphrase", key),
        ],
    );
    set_result(&app, "保存 WiFi 设置", ok);
}

#[tauri::command]
fn set_cellular(app: AppHandle, on: bool) {
    let id = if on {
        "CONNECT_NETWORK"
    } else {
        "DISCONNECT_NETWORK"
    };
    let ok = do_set("数据连接", &[("goformId", id.into())]);
    set_result(&app, if on { "拨号连接" } else { "断开数据" }, ok);
}

#[tauri::command]
fn set_network_mode(app: AppHandle, mode: String) {
    let ok = do_set(
        "切换网络模式",
        &[
            ("goformId", "SET_BEARER_PREFERENCE".into()),
            ("BearerPreference", mode),
        ],
    );
    set_result(&app, "切换网络模式", ok);
}

#[tauri::command]
fn set_sim_mode(app: AppHandle, mode: i64) {
    let ok = do_set(
        "切换 SIM",
        &[
            ("goformId", "set_esim".into()),
            ("esimmode", mode.to_string()),
        ],
    );
    if ok {
        let _ = app.emit(
            "toast",
            json!({ "message": "已提交 SIM 切换，设备将重启，约 1 分钟内恢复", "error": false }),
        );
    } else {
        set_result(&app, "切换 SIM", false);
    }
}

#[tauri::command]
fn save_lan(
    app: AppHandle,
    ip: String,
    mask: String,
    dhcp: bool,
    start: String,
    end: String,
    lease: i64,
) {
    let mut form: Vec<(&str, String)> = vec![
        ("goformId", "DHCP_SETTING".into()),
        ("lanIp", ip),
        ("lanNetmask", mask),
        (
            "lanDhcpType",
            if dhcp { "SERVER" } else { "DISABLE" }.into(),
        ),
    ];
    if dhcp {
        form.push(("dhcpStart", start));
        form.push(("dhcpEnd", end));
        form.push(("dhcpLease", lease.to_string()));
    }
    form.push(("dhcp_reboot_flag", "1".into()));
    let ok = do_set("保存局域网设置", &form);
    set_result(&app, "保存局域网设置", ok);
}

#[tauri::command]
fn set_upnp(app: AppHandle, on: bool) {
    let ok = do_set(
        "设置 UPnP",
        &[
            ("goformId", "UPNP_SETTING".into()),
            ("upnp_setting_option", if on { "1" } else { "0" }.into()),
        ],
    );
    set_result(&app, if on { "开启 UPnP" } else { "关闭 UPnP" }, ok);
}

#[tauri::command]
fn save_dmz(app: AppHandle, on: bool, ip: String) {
    let mut form: Vec<(&str, String)> = vec![
        ("goformId", "DMZ_SETTING".into()),
        ("DMZEnabled", if on { "1" } else { "0" }.into()),
    ];
    if on {
        form.push(("DMZIPAddress", ip));
    }
    let ok = do_set("保存 DMZ 设置", &form);
    set_result(&app, "保存 DMZ 设置", ok);
}

#[tauri::command]
fn reboot(app: AppHandle) {
    let ok = do_set("重启设备", &[("goformId", "REBOOT_DEVICE".into())]);
    set_result(&app, "重启设备", ok);
}

#[tauri::command]
fn open_web() {
    let _ = std::process::Command::new("open")
        .arg(format!("http://{}", HOST))
        .spawn();
}

fn main() {
    let shared = Shared::new();

    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .manage(shared.clone())
        .setup(move |app| {
            let menu = Menu::with_items(
                app,
                &[
                    &MenuItem::with_id(app, "open", "打开面板", true, None::<&str>)?,
                    &MenuItem::with_id(app, "settings", "设置…", true, None::<&str>)?,
                    &MenuItem::with_id(app, "web", "网页管理", true, None::<&str>)?,
                    &MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?,
                ],
            )?;

            let _tray = TrayIconBuilder::with_id("main")
                .icon(draw_icon(0, false))
                .icon_as_template(true)
                .menu(&menu)
                .show_menu_on_left_click(false)
                .tooltip("PGY 随身 WiFi")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "open" => toggle_panel(app),
                    "settings" => {
                        open_settings(app.clone());
                    }
                    "web" => open_web(),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        toggle_panel(tray.app_handle());
                    }
                })
                .build(app)?;

            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let handle = app.handle().clone();
            spawn_poller(handle.clone(), shared.clone());

            // 截图/自动化测试用：--show-settings / --show-panel
            let args: Vec<String> = std::env::args().collect();
            if args.iter().any(|a| a == "--show-settings") {
                let h = handle.clone();
                thread::spawn(move || {
                    thread::sleep(Duration::from_millis(1200));
                    if let Some(win) = h.get_webview_window("settings") {
                        let _ = win.set_position(tauri::LogicalPosition::new(180.0, 120.0));
                        let _ = win.show();
                        let _ = win.set_focus();
                    }
                });
            }
            if args.iter().any(|a| a == "--show-panel") {
                let h = handle.clone();
                thread::spawn(move || {
                    thread::sleep(Duration::from_millis(1200));
                    toggle_panel(&h);
                });
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_status,
            open_settings,
            hide_panel,
            quit_app,
            set_wifi,
            save_wifi,
            set_cellular,
            set_network_mode,
            set_sim_mode,
            save_lan,
            set_upnp,
            save_dmz,
            reboot,
            open_web,
            set_admin_password,
            change_admin_password,
            get_apns,
            set_default_apn
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
