import 'dart:async';
import 'dart:io';

/// iOS 登录失败的根因修复。
///
/// Flutter/Dart 的 [HttpClient] 不像浏览器那样做 Happy Eyeballs 地址回退，
/// 在同时返回 A(IPv4) 与 AAAA(IPv6) 的双栈域名下，会死磕首选的 IPv6 地址。
/// 当该 IPv6 链路（常见于家庭宽带/内网穿透）不可达时，连接会一直挂到超时，
/// 表现就是「苹果手机连不上、安卓/浏览器正常」。
///
/// 这里自定义 [HttpClient.connectionFactory]，优先使用 IPv4 并在所有候选地址间
/// 并行竞速，取第一个成功连接，从根本上规避卡在 IPv6 上的问题。
/// 若环境只有 IPv6（查不到 A 记录），则回退到全量解析，不影响纯 IPv6 场景。
HttpClient createIosFriendlyHttpClient() {
  final client = HttpClient();
  client.connectionFactory = _ipv4PreferredConnectionFactory;
  return client;
}

Future<ConnectionTask<Socket>> _ipv4PreferredConnectionFactory(
  Uri url,
  String? proxyHost,
  int? proxyPort,
) async {
  final host = url.host;
  final port = url.port;

  List<InternetAddress> addresses;
  try {
    addresses = await InternetAddress.lookup(
      host,
      type: InternetAddressType.IPv4,
    );
  } catch (_) {
    addresses = const [];
  }

  // 没有 IPv4（纯 IPv6 环境）时，回退到全量解析。
  if (addresses.isEmpty) {
    try {
      addresses = await InternetAddress.lookup(host);
    } catch (_) {
      addresses = const [];
    }
  }

  // 兜底：极端情况下仍查不到地址，交给 Dart 默认逻辑处理。
  if (addresses.isEmpty) {
    return Socket.startConnect(host, port);
  }

  // 并行竞速所有候选地址，第一个成功者胜出；其余连接随后关闭，避免资源泄漏。
  final completer = Completer<ConnectionTask<Socket>>();
  var pending = addresses.length;

  for (final address in addresses) {
    ConnectionTask<Socket> task;
    try {
      task = Socket.startConnect(address, port);
    } catch (_) {
      pending -= 1;
      if (pending == 0 && !completer.isCompleted) {
        completer.completeError(SocketException('无法连接到 $host:$port'));
      }
      continue;
    }

    task.socket.then((socket) {
      if (!completer.isCompleted) {
        completer.complete(task);
      } else {
        socket.destroy();
      }
    }).catchError((_) {
      pending -= 1;
      if (pending == 0 && !completer.isCompleted) {
        completer.completeError(SocketException('无法连接到 $host:$port'));
      }
    });
  }

  return completer.future;
}
