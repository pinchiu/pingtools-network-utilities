import 'package:cupertino_ui/cupertino_ui.dart';

import 'localization.dart';
import 'theme.dart';

class ToolInfo {
  final String id;
  final String titleEn;
  final String titleZh;
  final String subtitleEn;
  final String subtitleZh;
  final IconData icon;
  final Color accent;
  final String? tag;

  const ToolInfo({
    required this.id,
    required this.titleEn,
    required this.titleZh,
    required this.subtitleEn,
    required this.subtitleZh,
    required this.icon,
    required this.accent,
    this.tag,
  });

  String title(BuildContext context) => context.isZh ? titleZh : titleEn;
  String subtitle(BuildContext context) => context.isZh ? subtitleZh : subtitleEn;
}

const List<ToolInfo> tools = [
  ToolInfo(
    id: 'ping',
    titleEn: 'Ping',
    titleZh: 'Ping 測試',
    subtitleEn: 'ICMP latency, loss & jitter',
    subtitleZh: 'ICMP 延遲、封包遺失與抖動',
    icon: CupertinoIcons.wifi,
    accent: AppAccents.cyan,
    tag: 'ICMP',
  ),
  ToolInfo(
    id: 'geo',
    titleEn: 'Geo Ping',
    titleZh: '地理 Ping',
    subtitleEn: 'Target location & latency',
    subtitleZh: '目標位置與延遲',
    icon: CupertinoIcons.map,
    accent: AppAccents.blue,
    tag: 'MAP',
  ),
  ToolInfo(
    id: 'trace',
    titleEn: 'Traceroute',
    titleZh: '路由追蹤',
    subtitleEn: 'Hop-by-hop network path',
    subtitleZh: '逐跳網路路徑',
    icon: CupertinoIcons.arrow_branch,
    accent: AppAccents.violet,
  ),
  ToolInfo(
    id: 'ports',
    titleEn: 'Port Scanner',
    titleZh: '連接埠掃描',
    subtitleEn: 'TCP ports & service banners',
    subtitleZh: 'TCP 連接埠與服務橫幅',
    icon: CupertinoIcons.square_grid_2x2,
    accent: AppAccents.amber,
  ),
  ToolInfo(
    id: 'dns',
    titleEn: 'DNS Lookup',
    titleZh: 'DNS 查詢',
    subtitleEn: 'A, AAAA, MX, TXT & more',
    subtitleZh: 'A、AAAA、MX、TXT 等紀錄',
    icon: CupertinoIcons.doc_text_search,
    accent: AppAccents.teal,
  ),
  ToolInfo(
    id: 'whois',
    titleEn: 'WHOIS',
    titleZh: 'WHOIS 查詢',
    subtitleEn: 'Domain & IP registration',
    subtitleZh: '網域與 IP 註冊資訊',
    icon: CupertinoIcons.search,
    accent: AppAccents.green,
  ),
  ToolInfo(
    id: 'subnet',
    titleEn: 'Subnet Scanner',
    titleZh: '子網路掃描',
    subtitleEn: 'Discover hosts on a subnet',
    subtitleZh: '探索子網內的裝置',
    icon: CupertinoIcons.antenna_radiowaves_left_right,
    accent: AppAccents.cyan,
    tag: 'LAN',
  ),
  ToolInfo(
    id: 'wol',
    titleEn: 'Wake-on-LAN',
    titleZh: '網路喚醒',
    subtitleEn: 'Wake devices by MAC address',
    subtitleZh: '用 MAC 位址喚醒裝置',
    icon: CupertinoIcons.power,
    accent: AppAccents.rose,
  ),
  ToolInfo(
    id: 'connection',
    titleEn: 'Connection Info',
    titleZh: '連線資訊',
    subtitleEn: 'Local & public network details',
    subtitleZh: '區域與公開網路資訊',
    icon: CupertinoIcons.info_circle,
    accent: AppAccents.blue,
  ),
  ToolInfo(
    id: 'http',
    titleEn: 'HTTP Inspector',
    titleZh: 'HTTP 檢查器',
    subtitleEn: 'Status, headers & TLS details',
    subtitleZh: '狀態、標頭與 TLS 資訊',
    icon: CupertinoIcons.link,
    accent: AppAccents.amber,
  ),
];

ToolInfo? toolById(String id) {
  for (final tool in tools) {
    if (tool.id == id) return tool;
  }
  return null;
}
