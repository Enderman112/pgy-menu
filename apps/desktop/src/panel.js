const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (id) => document.getElementById(id);

function num(v) { const n = parseFloat(v); return Number.isFinite(n) ? n : 0; }
function str(v) { return v === null || v === undefined ? "" : String(v); }

function fmtBytes(b) {
  b = Math.max(0, Number(b) || 0);
  const units = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (b >= 1024 && i < units.length - 1) { b /= 1024; i++; }
  return (i === 0 ? Math.round(b) : b.toFixed(b >= 100 ? 0 : 1)) + " " + units[i];
}
function fmtSpeed(v) { return fmtBytes(v) + "/s"; }
function duration(sec) {
  sec = Math.max(0, Number(sec) || 0);
  if (sec <= 0) return "--";
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  if (h > 0) return `${h} 小时 ${m} 分`;
  if (m > 0) return `${m} 分 ${s} 秒`;
  return `${s} 秒`;
}
function networkLabel(s) {
  const t = (str(s.sub_network_type) || str(s.network_type)).toUpperCase();
  if (t.includes("LTE")) return "4G LTE";
  if (t.includes("WCDMA") || t.includes("HSPA") || t.includes("SCDMA")) return "3G";
  if (t.includes("GSM") || t.includes("GPRS") || t.includes("EDGE")) return "2G";
  if (!t) return "--";
  return t;
}

function renderBars(bars, connected) {
  const host = $("bars");
  const levels = [26, 45, 64, 82, 100];
  host.innerHTML = "";
  for (let i = 0; i < 5; i++) {
    const el = document.createElement("i");
    el.style.height = levels[i] + "%";
    if (i < bars) {
      el.classList.add("on");
      if (bars <= 2) el.classList.add("bad");
      else if (bars === 3) el.classList.add("warn");
    }
    host.appendChild(el);
  }
}

function render(s) {
  if (!s || s.offline) {
    $("provider").textContent = "随身 WiFi";
    $("subtitle").textContent = "未连接设备";
    renderBars(0, false);
    return;
  }
  const bars = num(s.signalbar);
  const connected = str(s.ppp_status) === "ppp_connected";
  $("provider").textContent = str(s.network_provider) || "随身 WiFi";
  let sub = connected ? "已连接 · " + networkLabel(s) : (bars > 0 ? "未连接" : "无信号");
  if (connected && num(s.realtime_time) > 0) sub += " · 已连 " + duration(num(s.realtime_time));
  $("subtitle").textContent = sub;
  renderBars(bars, connected);

  $("rsrp").textContent = str(s.lte_rsrp) ? num(s.lte_rsrp) + " dBm" : "--";
  $("sinr").textContent = str(s.nv_sinr) ? num(s.nv_sinr) + " dB" : "--";
  $("rsrq").textContent = str(s.nv_rsrq) ? ((num(s.nv_rsrq) - 40) / 2).toFixed(1) + " dB" : "--";
  $("band").textContent = num(s.nv_band) > 0 ? "B" + num(s.nv_band) : "--";
  $("pci").textContent = str(s.nv_pci) || "--";
  $("net").textContent = networkLabel(s);

  $("rxSpeed").textContent = "↓ " + fmtSpeed(num(s.rx_speed));
  $("txSpeed").textContent = "↑ " + fmtSpeed(num(s.tx_speed));
  $("session").textContent = "本次 ↓" + fmtBytes(num(s.realtime_rx_bytes)) + " ↑" + fmtBytes(num(s.realtime_tx_bytes));
  $("monthly").textContent = "本月 ↓" + fmtBytes(num(s.monthly_rx_bytes)) + " ↑" + fmtBytes(num(s.monthly_tx_bytes));

  const wifiOn = str(s.wifi_cur_state) === "1";
  $("wifiName").textContent = wifiOn ? (str(s.SSID1) || "WiFi 已开启") : "WiFi 已关闭";
  $("wifiHint").textContent = wifiOn ? "热点运行中" : "热点关闭";
  $("wifiSwitch").classList.toggle("on", wifiOn);
  window.__lastWifiOn = wifiOn;
}

listen("status", (event) => render(event.payload));
invoke("get_status").then(render).catch(() => {});

$("wifiSwitch").addEventListener("click", () => {
  const on = !(window.__lastWifiOn === true);
  invoke("set_wifi", { on });
  setTimeout(() => invoke("get_status").then(render), 600);
});
$("btnSettings").addEventListener("click", () => invoke("open_settings"));
$("btnWeb").addEventListener("click", () => invoke("open_web"));
$("btnQuit").addEventListener("click", () => invoke("quit_app"));

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") invoke("hide_panel");
});
