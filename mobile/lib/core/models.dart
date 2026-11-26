enum PingMode { icmp, tcp }

class PingConfig {
  final String host;
  final int count;
  final int intervalMs;
  final int timeoutMs;
  final int packetSize;
  final int ttl;

  const PingConfig({
    required this.host,
    this.count = 0,
    this.intervalMs = 1000,
    this.timeoutMs = 1500,
    this.packetSize = 56,
    this.ttl = 64,
  });
}

class PingReply {
  final int seq;
  final double rttMs;
  final int? ttl;
  final int bytes;
  final String from;

  const PingReply({
    required this.seq,
    required this.rttMs,
    this.ttl,
    this.bytes = 56,
    required this.from,
  });
}

class PingSummary {
  final int sent;
  final int received;
  final double lossPercent;
  final double minMs;
  final double avgMs;
  final double maxMs;
  final double jitterMs;
  final double stdDevMs;

  const PingSummary({
    required this.sent,
    required this.received,
    required this.lossPercent,
    required this.minMs,
    required this.avgMs,
    required this.maxMs,
    required this.jitterMs,
    required this.stdDevMs,
  });
}

sealed class PingEvent {
  const PingEvent();
}

class PingStarted extends PingEvent {
  final String target;
  final String? resolvedIp;
  final PingMode mode;
  const PingStarted({required this.target, this.resolvedIp, required this.mode});
}

class PingReplyEvent extends PingEvent {
  final PingReply reply;
  const PingReplyEvent(this.reply);
}

class PingTimeoutEvent extends PingEvent {
  final int seq;
  const PingTimeoutEvent(this.seq);
}

class PingNoteEvent extends PingEvent {
  final String message;
  const PingNoteEvent(this.message);
}

class PingFinishedEvent extends PingEvent {
  final PingSummary summary;
  final List<PingReply> replies;
  const PingFinishedEvent(this.summary, this.replies);
}

class PingFailedEvent extends PingEvent {
  final String message;
  const PingFailedEvent(this.message);
}

// ---------------------------------------------------------------------------

class TraceConfig {
  final String host;
  final int maxHops;
  final int probesPerHop;
  final int timeoutMs;
  final bool resolveNames;

  const TraceConfig({
    required this.host,
    this.maxHops = 30,
    this.probesPerHop = 3,
    this.timeoutMs = 1500,
    this.resolveNames = true,
  });
}

class TraceHop {
  final int hop;
  final String? address;
  final String? hostname;
  final List<double> rtts;

  const TraceHop({
    required this.hop,
    this.address,
    this.hostname,
    this.rtts = const [],
  });
}

sealed class TraceEvent {
  const TraceEvent();
}

class TraceStarted extends TraceEvent {
  final String target;
  final String? resolvedIp;
  const TraceStarted({required this.target, this.resolvedIp});
}

class TraceHopFound extends TraceEvent {
  final TraceHop hop;
  const TraceHopFound(this.hop);
}

class TraceFinished extends TraceEvent {
  final List<TraceHop> hops;
  final bool reachedTarget;
  const TraceFinished(this.hops, this.reachedTarget);
}

class TraceFailed extends TraceEvent {
  final String message;
  const TraceFailed(this.message);
}

// ---------------------------------------------------------------------------

enum PortState { open, closed, filtered }

class PortScanConfig {
  final String host;
  final List<int> ports;
  final int concurrency;
  final int timeoutMs;
  final bool grabBanners;

  const PortScanConfig({
    required this.host,
    required this.ports,
    this.concurrency = 64,
    this.timeoutMs = 900,
    this.grabBanners = true,
  });
}

class PortResult {
  final int port;
  final PortState state;
  final String service;
  final String? banner;

  const PortResult({
    required this.port,
    required this.state,
    this.service = '',
    this.banner,
  });
}

class PortScanProgress {
  final int scanned;
  final int total;
  final List<PortResult> open;

  const PortScanProgress({
    required this.scanned,
    required this.total,
    required this.open,
  });
}

sealed class PortScanEvent {
  const PortScanEvent();
}

class PortScanStarted extends PortScanEvent {
  final String host;
  final String? resolvedIp;
  final int total;
  const PortScanStarted({required this.host, this.resolvedIp, required this.total});
}

class PortScanProgressEvent extends PortScanEvent {
  final PortScanProgress progress;
  const PortScanProgressEvent(this.progress);
}

class PortScanFinished extends PortScanEvent {
  final List<PortResult> results;
  final int durationMs;
  const PortScanFinished(this.results, this.durationMs);
}

class PortScanFailed extends PortScanEvent {
  final String message;
  const PortScanFailed(this.message);
}

// ---------------------------------------------------------------------------

enum DnsType { a, aaaa, cname, mx, ns, txt, soa, srv, caa, ptr }

extension DnsTypeLabel on DnsType {
  String get label => name.toUpperCase();
}

class DnsRecord {
  final String type;
  final String value;
  final int? ttl;

  const DnsRecord({required this.type, required this.value, this.ttl});
}

class DnsResult {
  final String query;
  final DnsType type;
  final String resolver;
  final List<DnsRecord> records;
  final int durationMs;
  final String? error;

  const DnsResult({
    required this.query,
    required this.type,
    required this.resolver,
    this.records = const [],
    this.durationMs = 0,
    this.error,
  });
}

// ---------------------------------------------------------------------------

class WhoisField {
  final String key;
  final String value;
  const WhoisField(this.key, this.value);
}

class WhoisResult {
  final String query;
  final String server;
  final String raw;
  final List<WhoisField> fields;
  final int durationMs;
  final String? error;

  const WhoisResult({
    required this.query,
    required this.server,
    this.raw = '',
    this.fields = const [],
    this.durationMs = 0,
    this.error,
  });
}

// ---------------------------------------------------------------------------

class SubnetConfig {
  final String cidr;
  final bool includePortProbe;
  final List<int> probePorts;
  final int timeoutMs;
  final int concurrency;

  const SubnetConfig({
    required this.cidr,
    this.includePortProbe = false,
    this.probePorts = const [22, 80, 443, 445, 3389, 8080],
    this.timeoutMs = 350,
    this.concurrency = 48,
  });
}

class LanHost {
  final String ip;
  final String? mac;
  final String? hostname;
  final double? rttMs;
  final List<int> openPorts;
  final bool isGateway;

  const LanHost({
    required this.ip,
    this.mac,
    this.hostname,
    this.rttMs,
    this.openPorts = const [],
    this.isGateway = false,
  });

  LanHost copyWith({
    String? mac,
    String? hostname,
    double? rttMs,
    List<int>? openPorts,
  }) {
    return LanHost(
      ip: ip,
      mac: mac ?? this.mac,
      hostname: hostname ?? this.hostname,
      rttMs: rttMs ?? this.rttMs,
      openPorts: openPorts ?? this.openPorts,
      isGateway: isGateway,
    );
  }
}

class SubnetInfo {
  final String cidr;
  final String localIp;
  final int prefixLength;
  final String? gateway;
  final int totalHosts;

  const SubnetInfo({
    required this.cidr,
    required this.localIp,
    required this.prefixLength,
    this.gateway,
    this.totalHosts = 0,
  });

  SubnetInfo copyWith({String? gateway}) => SubnetInfo(
        cidr: cidr,
        localIp: localIp,
        prefixLength: prefixLength,
        gateway: gateway ?? this.gateway,
        totalHosts: totalHosts,
      );
}

sealed class SubnetScanEvent {
  const SubnetScanEvent();
}

class SubnetScanStarted extends SubnetScanEvent {
  final SubnetInfo info;
  const SubnetScanStarted(this.info);
}

class SubnetScanProgress extends SubnetScanEvent {
  final int scanned;
  final int total;
  final List<LanHost> found;
  const SubnetScanProgress({required this.scanned, required this.total, required this.found});
}

class SubnetScanFinished extends SubnetScanEvent {
  final List<LanHost> hosts;
  final int durationMs;
  const SubnetScanFinished(this.hosts, this.durationMs);
}

class SubnetScanFailed extends SubnetScanEvent {
  final String message;
  const SubnetScanFailed(this.message);
}

// ---------------------------------------------------------------------------

class WolDevice {
  final String name;
  final String mac;
  final String broadcast;
  final int port;

  const WolDevice({
    required this.name,
    required this.mac,
    this.broadcast = '255.255.255.255',
    this.port = 9,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'mac': mac,
        'broadcast': broadcast,
        'port': port,
      };

  factory WolDevice.fromJson(Map<String, dynamic> json) => WolDevice(
        name: json['name'] as String? ?? 'Device',
        mac: json['mac'] as String? ?? '',
        broadcast: json['broadcast'] as String? ?? '255.255.255.255',
        port: (json['port'] as num?)?.toInt() ?? 9,
      );
}

class WolOutcome {
  final String mac;
  final String address;
  final int port;
  final int packetsSent;

  const WolOutcome({
    required this.mac,
    required this.address,
    required this.port,
    required this.packetsSent,
  });
}

// ---------------------------------------------------------------------------

class WifiDetails {
  final String? ssid;
  final String? bssid;
  final int? rssiDbm;
  final int? linkSpeedMbps;
  final int? frequencyMhz;

  const WifiDetails({
    this.ssid,
    this.bssid,
    this.rssiDbm,
    this.linkSpeedMbps,
    this.frequencyMhz,
  });
}

class ConnectionInfo {
  final String connectionType;
  final String? localIpv4;
  final String? localIpv6;
  final int? prefixLength;
  final String? gateway;
  final List<String> dnsServers;
  final WifiDetails? wifi;
  final String? mobileOperator;
  final bool isVpn;

  const ConnectionInfo({
    required this.connectionType,
    this.localIpv4,
    this.localIpv6,
    this.prefixLength,
    this.gateway,
    this.dnsServers = const [],
    this.wifi,
    this.mobileOperator,
    this.isVpn = false,
  });
}

class PublicIpInfo {
  final String? ip;
  final String? isp;
  final String? org;
  final String? asn;
  final String? city;
  final String? region;
  final String? country;
  final String? countryCode;
  final double? lat;
  final double? lon;
  final String? timezone;
  final String? error;

  const PublicIpInfo({
    this.ip,
    this.isp,
    this.org,
    this.asn,
    this.city,
    this.region,
    this.country,
    this.countryCode,
    this.lat,
    this.lon,
    this.timezone,
    this.error,
  });
}

class HttpInfo {
  final String url;
  final String finalUrl;
  final int statusCode;
  final String statusMessage;
  final String protocol;
  final String? server;
  final String? contentType;
  final int? contentLength;
  final int durationMs;
  final String? tlsVersion;
  final String? tlsCipher;
  final List<List<String>> headers;
  final List<List<String>> security;
  final String? error;

  const HttpInfo({
    required this.url,
    this.finalUrl = '',
    this.statusCode = 0,
    this.statusMessage = '',
    this.protocol = '',
    this.server,
    this.contentType,
    this.contentLength,
    this.durationMs = 0,
    this.tlsVersion,
    this.tlsCipher,
    this.headers = const [],
    this.security = const [],
    this.error,
  });
}

// ---------------------------------------------------------------------------

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String tag;
  final String releaseNotes;
  final String? apkUrl;
  final String? sha256Url;
  final String? htmlUrl;
  final bool hasUpdate;
  final String? error;

  const UpdateInfo({
    required this.currentVersion,
    this.latestVersion = '',
    this.tag = '',
    this.releaseNotes = '',
    this.apkUrl,
    this.sha256Url,
    this.htmlUrl,
    this.hasUpdate = false,
    this.error,
  });
}

enum InstallStatus { launched, permissionRequired, error }

class InstallOutcome {
  final InstallStatus status;
  final String? message;
  const InstallOutcome(this.status, [this.message]);
}
