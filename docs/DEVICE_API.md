# PGY / X4U 随身 WiFi Web API 逆向记录

设备：`X4U` 系列 USB / WiFi 随身路由器（Unisoc / Sanechips 方案，Web 服务器头 `Sanechips-Webs`，界面框架 ZTE UFI WebUI，Oray 定制皮肤）
- 管理地址：`http://10.168.1.1/`（USB 网卡接口名 `DEMO Mobile Boardband`，网关 10.168.1.1）
- 固件：`X4U_DV7_1COT0S_T3_16010`，硬件 `X4U_V1.2`，Web `X4U_M01.210408`
- 默认管理员：`admin` / `admin`（`login_mode=admin`，登录无 Cookie，按客户端 IP 维持会话）

## 1. 读取：GOFORM_GET

```
GET /goform/goform_get_cmd_process?isTest=false&multi_data=1&cmd=a,b,c,...
```

返回 `{"a":"...","b":"...",...}`；部分字段需要登录（未登录时返回 `""`）。

### 免登录即可读（信号/流量/连接态）
```
signalbar,network_type,sub_network_type,ppp_status,modem_main_state,cpin,simcard_roam,
network_provider,wifi_cur_state,has_wifi,
lte_rsrp,rssi,rscp,nv_rsrq,nv_sinr,nv_band,nv_bandwidth,nv_arfcn,nv_pci,nv_cellid,nv_globecellid,nv_cqi0,
realtime_tx_bytes,realtime_rx_bytes,realtime_time,realtime_tx_thrpt,realtime_rx_thrpt,
monthly_tx_bytes,monthly_rx_bytes,monthly_time,traffic_alined_delta,
data_volume_limit_switch,data_volume_limit_unit,data_volume_limit_size,data_volume_alert_percent,
roam_setting_option,run_time
```
实测样例（LTE 中国移动）：
```json
{"signalbar":"5","network_type":"LTE","sub_network_type":"FDD_LTE","ppp_status":"ppp_connected",
 "lte_rsrp":"-73","nv_rsrq":"28","nv_sinr":"14","nv_band":"3","nv_bandwidth":"1",
 "nv_arfcn":"1300","nv_pci":"403","nv_cellid":"137","nv_globecellid":"263486089"}
```

### 需要登录才能读
```
loginfo(=ok 表示已登录),Language,SSID1,HideSSID,AuthMode,EncrypType,WPAPSK1_encode(Base64 密码),
MAX_Access_num,WirelessMode,Channel,wifi_coverage,Sleep_interval,MAX_Station_num,
imei,imsi,msisdn,ziccid,cr_version,hw_version,web_version,
net_select,current_network_mode,net_select_mode,
data_volume_* ,lan_ipaddr,dhcpEnabled,dhcpStart,dhcpEnd,login_mode,
LteBandLockSet,LteBandLockState,band_1..band_41,amt_band_1..amt_band_41
```

## 2. 写入：GOFORM_SET

```
POST /goform/goform_set_cmd_process
Content-Type: application/x-www-form-urlencoded
isTest=false&goformId=<ID>&<参数...>
```
成功：`{"result":"success"}`，失败：`{"result":"failure"}`。未登录时写入一律 `failure`。

| 功能 | goformId | 参数 |
|---|---|---|
| 登录 | `LOGIN` | `username`=Base64(用户名), `password`=Base64(密码)；`result":"0"` 成功 |
| 注销 | `LOGOUT` | – |
| WiFi 开/关 | `SET_WIFI_INFO` | `wifiEnabled=0/1`（开启时可带 `m_ssid_enable=0`） |
| WiFi 名称/密码 | `SET_WIFI_SSID1_SETTINGS` | `ssid`,`broadcastSsidEnabled=0/1`,`MAX_Access_num`,`security_mode`=AuthMode,`cipher`,`NoForwarding`,`show_qrcode_flag`,`security_shared_mode`=`cipher`,`passphrase`=Base64(密码) |
| WiFi 密码(仅改密码) | `SET_WIFI_SECURITY_INFO` | `AuthMode`,`passPhrase`=Base64 |
| WiFi 覆盖 | `SET_WIFI_COVERAGE` | `wifi_coverage`=`long_mode`/`medium_mode`/`short_mode` |
| WiFi 休眠 | `SET_WIFI_SLEEP_INFO` | `sysIdleTimeToSleep`=-1/5/10/20/30/60/120（分钟） |
| 拨号连接 | `CONNECT_NETWORK` / `DISCONNECT_NETWORK` | – |
| 网络模式 | `SET_BEARER_PREFERENCE` | `BearerPreference`：`NETWORK_auto` / `Only_LTE` / `TD_LTE_auto` |
| 频段锁定 | `SET_LOCK_LTE_BAND_MODE` | `band1`..`band41` = `0`/`1`（1=允许该频段） |
| 流量限额 | `DATA_LIMIT_SETTING` | `data_volume_limit_switch=0/1`；开启时 `data_volume_limit_unit`=`data`/`time`,`data_volume_limit_size`,`data_volume_alert_percent` |
| APN 列表 | `GET` cmd=`APN_config0..19` | 每项以 `($)` 分隔 |
| APN 切换默认 | `APN_PROC_EX` | `apn_mode=manual&apn_action=set_default&set_default_flag=1&pdp_type=<IP/IPv6/IPv4v6>&index=<n>` |
| APN 保存 | `APN_PROC_EX` | `apn_mode=manual&apn_action=save&profile_name&wan_dial=*99#&pdp_type&pdp_select=auto&index&wan_apn&ppp_auth_mode&ppp_username&ppp_passwd` |
| 重启 | `REBOOT_DEVICE` | – |
| 关机 | `TURN_OFF_DEVICE` | – |
| 恢复出厂 | `RESTORE_FACTORY_SETTINGS` | – |
| 修改管理密码 | `CHANGE_PASSWORD` | `newPassword`=Base64, `oldPassword`=Base64 |
| 短信已读 | `SET_MSG_READ` | `msg_id=<id1>;<id2>;`（注意末尾分号）, `tag=0` |
| 发短信 | `SEND_SMS` | `Number`,`sms_time=yy;MM;dd;HH;mm;ss;±TZ`,`MessageBody`=UTF-16 十六进制串,`ID=-1`,`encode_type`=`UNICODE`/`GSM7_default`,`notCallback=true` |
| 删除短信 | `DELETE_SMS` | `msg_id=...;`,`notCallback=true` |
| 语言 | `SET_WEB_LANGUAGE` | `Language=zh-cn/en` |

## 3. 短信（本机未启用）

> 实测本机（X4U / X4U_DV7_1COT0S_T3_16010）短信模块未启用：
> `sms_capacity_info` 全部为 0、`sms_parameter_info` 中各字段为空、
> `SET_MESSAGE_CENTER` 返回 `failure`、`sms_cmd_status_info` 返回空。
> 因此本 App 不做短信功能。

### 设备 WebUI 原本的短信接口（备用）

```
GET /goform/goform_get_cmd_process?isTest=false&cmd=sms_data_total&page=0&data_per_page=200&mem_store=1&tags=10&order_by=order by id desc
```
`messages[]` 字段：`id`,`number`,`content`（UTF-16 十六进制，需解码，跳过 0009/0000）,`date`=`yy,MM,dd,HH,mm,ss,±TZ`,`tag`（1=收件未读 2=已发送 3=发送失败 4=草稿）,`received_all_concat_sms`,`draft_group_id`。
未读数：`cmd=sms_dev_unread_num`（未登录/为空时视为 0）。

## 3.5 局域网 / UPnP / DMZ / SIM 切换

| 功能 | 读取 cmd | 写入 |
|---|---|---|
| 局域网 / DHCP | `lan_ipaddr,lan_netmask,dhcpEnabled,dhcpStart,dhcpEnd,dhcpLease_hour,mac_address` | `DHCP_SETTING`：`lanIp`,`lanNetmask`,`lanDhcpType`=`SERVER`/`DISABLE`（服务时带 `dhcpStart`,`dhcpEnd`,`dhcpLease`），`dhcp_reboot_flag=1` |
| UPnP | `upnpEnabled` | `UPNP_SETTING`：`upnp_setting_option=1/0` |
| DMZ | `DMZEnable,DMZIPAddress` | `DMZ_SETTING`：`DMZEnabled=1/0`，开启时带 `DMZIPAddress` |
| 内置/外置 SIM | `sim_esim_mode`（0=外置实体卡，1=内置 eSIM）、`user_web_disp_sim_esim_config`（是否显示该功能） | `set_esim`：`esimmode=0/1`。**切换后设备会重启约 40~60 秒**，`sim_esim_mode` 期间可能短暂为空 |

实测（X4U）：`set_esim` 返回 `success` 后设备断开重连，Web 管理/USB 网卡恢复后 `sim_esim_mode` 变为新值；把内置 eSIM 切回外置后 `ppp_status=ppp_connected`、运营商恢复 China Mobile。

## 4. 信号数值换算（来自 `js/util.js`）

- RSRP：`lte_rsrp`，单位 dBm，直接显示（如 -73 dBm）
- RSRQ：`(nv_rsrq - 40) / 2` dB（28 → -6 dB）
- SINR：`nv_sinr` dB
- 2G：`rssi`；3G：`rscp` → `rscp-116` dBm
- 信号格：`signalbar` 0..5
- 频段：`Band` + `nv_band`；EARFCN `nv_arfcn`；PCI `nv_pci`；CellID `nv_cellid`
- 吞吐：`realtime_tx_thrpt` / `realtime_rx_thrpt`（字节/秒）
- 流量：`realtime_*_bytes`=本次连接累计；`monthly_*_bytes`=本月累计；`monthly_time`=本月在线秒数

## 5. 其他

- 设备静态文件：`/js/...`、`/tmpl/...`、`/config/...`（可直接下载分析）
- 无 Cookie 会话，登录态按客户端 IP 维持，同一网段下任意客户端登录即为全局登录。
- 状态轮询可用短连接，1~3 秒一次；设备 Web 服务器为 `HTTP/1.0`，不支持 `Accept-Encoding` 之外的花活，尽量保持简单 GET/POST。
