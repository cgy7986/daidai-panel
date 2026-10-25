import 'dart:async';
import 'dart:io';

/// iOS 登录失败的根因修复。
///
/// Flutter/Dart 的 [HttpClient] 在双栈（IPv4 + IPv6）域名下不会做 Happy Eyeballs
/// （同时竞速两种地址族），而是单一地址尝试；当首选地址不可达时（常见：家庭宽带/
/// 内网穿透下 IPv6 不通，或反之 iPhone 处于 IPv6 优先网络、面板仅 IPv6 可达）就会一直
/// 卡到超时，表现就是「苹果手机连不上、安卓/浏览器正常」。
///
/// 这里自定义 [HttpClient.connectionFactory]，并行竞速**所有**候选地址
/// （IPv4 与 IPv6 同时参与、谁先连上用谁），其余连接随后关闭，避免资源泄漏。
/// 因此无论面板通过 IPv4 还是 IPv6 可达都能连上，且不依赖某一族一定可用。
HttpClient createIosFriendlyHttpClient() {
  final client = HttpClient();
  client.connectionFactory = _happyEyeballsConnectionFactory;
  return client;
}

Future<ConnectionTask<Socket>> _happyEyeballsConnectionFactory(
  Uri url,
  String? proxyHost,
  int? proxyPort,
) async {
  final host = url.host;
  final port = url.port;

  // 并行解析 IPv4 与 IPv6，任一族解析失败不影响另一族。
  final results = await Future.wait<Iterable<InternetAddress>>([
    InternetAddress.lookup(host, type: InternetAddressType.IPv4)
        .then((v) => v as Iterable<InternetAddress>)
        .catchError((_) => <InternetAddress>[]),
    InternetAddress.lookup(host, type: InternetAddressType.IPv6)
        .then((v) => v as Iterable<InternetAddress>)
        .catchError((_) => <InternetAddress>[]),
  ]);

  final addresses = <InternetAddress>[...results[0], ...results[1]];

  // 兜底：完全解析不到任何地址时，交给 Dart 默认逻辑（让上层拿到明确错误）。
  if (addresses.isEmpty) {
    return Socket.startConnect(host, port);
  }

  final completer = Completer<ConnectionTask<Socket>>();
  var pending = addresses.length;
  var settled = false;

  // 安全闸：即使所有连接都“挂死”也不让上层无限等待（避免界面一直转圈）。
  final guard = Timer(const Duration(seconds: 12), () {
    if (!completer.isCompleted) {
      completer.completeError(SocketException('连接 $host:$port 超时'));
    }
  });

  void settleSuccess(ConnectionTask<Socket> task) {
    if (!settled) {
      settled = true;
      guard.cancel();
      completer.complete(task);
    } else {
      // 多余连接：连上了也立即销毁，避免泄漏。
      task.socket.then((socket) => socket.destroy()).catchError((_) {});
    }
  }

  void onOneFailed() {
    pending -= 1;
    if (pending <= 0 && !completer.isCompleted) {
      guard.cancel();
      completer.completeError(
        SocketException('无法连接到 $host:$port（所有地址均不可达）'),
      );
    }
  }

  for (final address in addresses) {
    Future<ConnectionTask<Socket>> taskFuture;
    try {
      taskFuture = Socket.startConnect(address, port);
    } catch (_) {
      onOneFailed();
      continue;
    }
    taskFuture.then((task) {
      task.socket.then((socket) {
        if (!settled) {
          settled = true;
          guard.cancel();
          completer.complete(task);
        } else {
          socket.destroy();
        }
      }).catchError((_) => onOneFailed());
    }).catchError((_) => onOneFailed());
  }

  return completer.future;
}
