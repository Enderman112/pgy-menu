const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (id) => document.getElementById(id);
const num = (v) => { const n = parseFloat(v); return Number.isFinite(n) ? n : 0; };
const str = (v) => (v === null || v === undefined ? "" : String(v));

function fmtBytes(b) {
  b = Math.max(0, Number(b) || 0);
  const units = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (b >= 1024 && i < units.length - 1) { b /= 1024; i++; }
  return (i === 0 ? Math.round(b) : b.toFixed(b >= 100 ? 0 : 1)) + " " + units[i];
}
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
function quality(bars) {
  return ["无信号", "很弱", "较弱", "一般", "良好", "极佳"][Math.max(0, Math.min(5, bars))] || "无信号";
}
function renderBars(host, bars) {
  const levels = [26, 45, 64, 82, 100];
  host.innerHTML = "";
  for (let i = 0; i < 5; i++) {
    const el = document.createElement("i");
    el.style.height = levels[i] + "%";
    el.style.width = "8px";
    if (i < bars) {
      el.classList.add("on");
      if (bars <= 2) el.classList.add("bad");
      else if (bars === 3) el.classList.add("warn");
    }
    host.appendChild(el);
  }
}

let state = {};

function render(s) {
  if (!s || s.offline) {
    $("headSub").textContent = "未连接设备（检查 USB 与 10.168.1.1）";
    return;
  }
  state = s;
  const bars = num(s.signalbar);
  const connected = str(s.ppp_status) === "ppp_connected";

  $("headSub").textContent = `10.168.1.1 · ${str(s.network_provider) || "设备已连接"}`;
  renderBars($("bigBars"), bars);
  $("quality").textContent = quality(bars);
  $("qualitySub").textContent = `${bars}/5 格 · ${networkLabel(s)}`;
  $("oRsrp").textContent = str(s.lte_rsrp) ? num(s.lte_rsrp) + " dBm" : "--";
  $("oSinr").textContent = str(s.nv_sinr) ? num(s.nv_sinr) + " dB" : "--";
  $("oRsrq").textContent = str(s.nv_rsrq) ? ((num(s.nv_rsrq) - 40) / 2).toFixed(1) + " dB" : "--";
  $("oBand").textContent = num(s.nv_band) > 0 ? "B" + num(s.nv_band) : "--";
  $("oPci").textContent = str(s.nv_pci) || "--";
  $("oNet").textContent = networkLabel(s);

  $("oStatus").textContent = connected ? "已连接" : (bars > 0 ? "未连接" : "无信号");
  $("oStatus").style.color = connected ? "#2fa84f" : "#8e8e93";
  $("oDuration").textContent = num(s.realtime_time) > 0 ? "已连 " + duration(num(s.realtime_time)) : "--";
  $("oProvider").textContent = str(s.network_provider) || "--";
  $("oNetwork").textContent = networkLabel(s);
  $("oImei").textContent = str(s.imei) || "--";
  $("oPhone").textContent = str(s.msisdn) || "--";
  $("oIccid").textContent = str(s.ziccid) || "--";
  $("oFirmware").textContent = str(s.cr_version) || "--";
  $("oHardware").textContent = str(s.hw_version) || "--";
  $("oUptime").textContent = duration(num(s.run_time));

  // 通信状态
  $("dataStatus").textContent = connected
    ? `已连接 · ${networkLabel(s)} · ${str(s.network_provider)}`
    : (bars > 0 ? "未连接（可拨号）" : "无信号");
  $("btnData").textContent = connected ? "断开数据" : "拨号连接";

  // SIM
  const simMode = num(s.sim_esim_mode);
  document.querySelectorAll("#simSeg button").forEach((b) => {
    b.classList.toggle("active", Number(b.dataset.sim) === simMode);
  });
  $("simCurrent").textContent = `当前使用：${simMode === 1 ? "内置 SIM（eSIM）" : "外置 SIM（实体卡）"}`;
  $("btnSim").disabled = str(s.user_web_disp_sim_esim_config) !== "1";

  // WiFi
  if (document.activeElement !== $("wifiSsid")) $("wifiSsid").value = str(s.SSID1);
  const wifiOn = str(s.wifi_cur_state) === "1";
  $("wifiEnable").classList.toggle("on", wifiOn);

  // 路由
  if (document.activeElement !== $("lanIp")) $("lanIp").value = str(s.lan_ipaddr);
  if (document.activeElement !== $("lanMask")) $("lanMask").value = str(s.lan_netmask);
  $("dhcpOn").checked = str(s.dhcpEnabled) !== "0";
  if (document.activeElement !== $("dhcpStart")) $("dhcpStart").value = str(s.dhcpStart);
  if (document.activeElement !== $("dhcpEnd")) $("dhcpEnd").value = str(s.dhcpEnd);
  const lease = num(s.dhcpLease_hour);
  if (lease > 0) $("leaseSelect").value = String(lease);
  $("upnpOn").checked = str(s.upnpEnabled) === "1";
  $("dmzOn").checked = str(s.DMZEnable) === "1";
  if (document.activeElement !== $("dmzIp")) $("dmzIp").value = str(s.DMZIPAddress);
}

listen("status", (e) => render(e.payload));
listen("toast", (e) => showToast(e.payload.message, e.payload.error));
invoke("get_status").then(render).catch(() => {});

let toastTimer = null;
function showToast(text, error) {
  const el = $("toast");
  el.textContent = text;
  el.classList.toggle("error", !!error);
  el.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("show"), 2600);
}

// tabs
document.querySelectorAll("#tabs button").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.querySelectorAll("#tabs button").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    document.querySelectorAll(".page").forEach((p) => p.classList.remove("active"));
    $("page-" + btn.dataset.tab).classList.add("active");
  });
});

// actions
$("btnRefresh").addEventListener("click", () => invoke("get_status").then(render));
$("btnWebTop").addEventListener("click", () => invoke("open_web"));
$("btnData").addEventListener("click", () => {
  invoke("set_cellular", { on: str(state.ppp_status) !== "ppp_connected" });
});
$("btnData2").addEventListener("click", () => {
  invoke("set_cellular", { on: str(state.ppp_status) !== "ppp_connected" });
});
$("btnMode").addEventListener("click", () => invoke("set_network_mode", { mode: $("modeSelect").value }));
$("btnSim").addEventListener("click", () => {
  const active = document.querySelector("#simSeg button.active");
  const mode = Number(active ? active.dataset.sim : 0);
  if (!confirm("切换 SIM 会让设备重启、网络中断约 1 分钟，确定吗？")) return;
  invoke("set_sim_mode", { mode });
});
document.querySelectorAll("#simSeg button").forEach((b) => {
  b.addEventListener("click", () => {
    document.querySelectorAll("#simSeg button").forEach((x) => x.classList.remove("active"));
    b.classList.add("active");
  });
});
$("wifiEnable").addEventListener("click", () => {
  invoke("set_wifi", { on: str(state.wifi_cur_state) !== "1" });
});
$("btnWifiSave").addEventListener("click", () => {
  invoke("save_wifi", {
    ssid: $("wifiSsid").value.trim(),
    password: $("wifiPwd").value,
    hidden: $("wifiHidden").checked,
  });
  $("wifiPwd").value = "";
});
$("btnLanSave").addEventListener("click", () => {
  invoke("save_lan", {
    ip: $("lanIp").value.trim(),
    mask: $("lanMask").value.trim(),
    dhcp: $("dhcpOn").checked,
    start: $("dhcpStart").value.trim(),
    end: $("dhcpEnd").value.trim(),
    lease: Number($("leaseSelect").value),
  });
});
$("upnpOn").addEventListener("change", () => invoke("set_upnp", { on: $("upnpOn").checked }));
$("btnDmzSave").addEventListener("click", () => {
  invoke("save_dmz", { on: $("dmzOn").checked, ip: $("dmzIp").value.trim() });
});
$("btnReboot").addEventListener("click", () => {
  if (!confirm("确定重启设备？网络会中断约 30 秒。")) return;
  invoke("reboot");
});
$("btnWeb").addEventListener("click", () => invoke("open_web"));
$("btnQuit").addEventListener("click", () => invoke("quit_app"));
