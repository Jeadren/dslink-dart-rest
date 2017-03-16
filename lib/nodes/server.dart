import 'dart:async';
import 'dart:io' show WebSocket;
import "dart:typed_data";
import 'dart:convert' show BASE64, JSON;

import 'package:dslink/dslink.dart';
import 'package:dslink/utils.dart' show logger;

import 'create_value.dart';
import 'remove.dart';

import '../server.dart';
import '../node_manager.dart';

class AddServer extends SimpleNode {
  static const String isType = 'addServer';
  static const String pathName = 'Add_Server';

  static const String _name = 'name';
  static const String _local = 'local';
  static const String _port = 'port';
  static const String _type = 'type';
  static const String _user = 'username';
  static const String _pass = 'password';
  static const String _success = 'success';
  static const String _message = 'message';

  static Map<String, dynamic> def() => {
        r'$is': isType,
        r"$name": "Add Server",
        r"$invokable": "write",
        r"$params": [
          {"name": _name, "type": "string", "placeholder": "MyServer"},
          {
            "name": _local,
            "type": "bool",
            "description": "Bind to Local Interface",
            "default": false
          },
          {"name": _port, "type": "number", 'editor': 'int', "default": 8020},
          {
            "name": _type,
            "type": "enum[${ServerNode.DataHost},${ServerNode.DataClient}]",
            "default": "Data Host",
            "description": "Data Type"
          },
          {"name": _user, "type": "string", "placeholder": "Optional Username"},
          {
            "name": _pass,
            "type": "string",
            "editor": "password",
            "placeholder": "Optional Password"
          }
        ],
        r"$result": "values",
        r"$columns": [
          {"name": _success, "type": "bool", 'default': false},
          {'name': _message, 'type': 'string', 'default': ''}
        ],
      };

  final LinkProvider link;

  AddServer(String path, this.link) : super(path);

  @override
  Future<Map<String, dynamic>> onInvoke(Map<String, dynamic> params) async {
    var ret = {_success: false, _message: ''};

    int port =
        params["port"] is String ? int.parse(params["port"]) : params["port"];
    bool local = params["local"];
    String type = params["type"];
    String pwd = params["password"];
    String user = params["username"];
    if (local == null) local = false;

    ret[_success] = await Server.checkPort(port);
    if (!ret[_success]) {
      return ret..[_message] = "Unable to bind to port";
    }

    if (user == null || user.isEmpty) user = 'dsa';

    provider.addNode(
        '/${params[_name]}', ServerNode.def(port, local, type, user, pwd));

    link.saveAsync();

    ret[_success] = 'Success';
    return ret;
  }
}

class EditServer extends SimpleNode {
  static const String isType = 'editServer';
  static const String pathName = 'Edit_Server';

  static const String _local = 'local';
  static const String _port = 'port';
  static const String _type = 'type';
  static const String _user = 'username';
  static const String _pass = 'password';
  static const String _success = 'success';
  static const String _message = 'message';

  static Map<String, dynamic> def(
          bool local, int port, String type, String user) =>
      {
        r'$is': isType,
        r'$name': 'Edit Server',
        r'$invokable': 'write',
        r'$params': [
          {
            "name": _local,
            "type": "bool",
            "description": "Bind to Local Interface",
            "default": local
          },
          {"name": _port, "type": "number", 'editor': 'int', "default": port},
          {
            "name": _type,
            "type": "enum[${ServerNode.DataHost},${ServerNode.DataClient}]",
            "default": type,
            "description": "Data Type"
          },
          {
            "name": _user,
            "type": "string",
            'default': user,
            "placeholder": "Optional Username"
          },
          {
            "name": _pass,
            "type": "string",
            "editor": "password",
            'description': 'Leaving this blank will use any previous password',
            "placeholder": "Optional Password"
          }
        ],
        r'$columns': [
          {'name': _success, 'type': 'bool', 'default': false},
          {'name': _message, 'type': 'string', 'default': ''}
        ]
      };

  EditServer(String path) : super(path);

  @override
  Future<Map<String, dynamic>> onInvoke(Map<String, dynamic> params) async {
    final ret = {_success: false, _message: ''};

    int port;
    if (params[_port] is int) {
      port = params[_port];
    } else if (params[_port] is num) {
      port = (params[_port] as num).toInt();
    } else {
      port = int.parse(params[_port], onError: (_) => null);
    }

    bool loc = params[_local] as bool;
    String ty = params[_type] as String;
    String u = params[_user] as String;
    String p = params[_pass] as String;

    var err = await (parent as ServerNode).updateConfig(port, loc, ty, u, p);

    if (err == null) {
      ret
        ..[_success] = true
        ..[_message] = 'Success!';
    } else {
      ret
        ..[_success] = false
        ..[_message] = 'Unable to update config: $err';
    }

    return ret;
  }
}

class ServerNode extends SimpleNode implements NodeManager {
  static const String isType = 'server';

  /// ServerNode acts as a Data Host
  static const String DataHost = 'Data Host';

  /// ServerNode acts as a Data Client
  static const String DataClient = 'Data Client';

  static const String _port = r'$server_port';
  static const String _local = r'$server_local';
  static const String _type = r'$server_type';
  static const String _user = r'$$server_username';
  static const String _pass = r'$$server_password';

  static const Duration _timeout = const Duration(seconds: 5);

  static Map<String, dynamic> def(
      int port, bool local, String type, String user, String pass) {
    var ret = <String, dynamic>{
      r'$is': isType,
      _port: port,
      _local: local,
      _type: type,
      _user: user,
      _pass: pass,
      RemoveNode.pathName: RemoveNode.def(),
      EditServer.pathName: EditServer.def(local, port, type, user)
    };

    if (type.toLowerCase() == 'data host') {
      ret[CreateNode.pathName] = CreateNode.def();
      ret[CreateValue.pathName] = CreateValue.def();
    }
    return ret;
  }

  Server server;

  final LinkProvider link;
  bool isDataHost = false;
  ServerNode(String path, this.link) : super(path);

  @override
  onCreated() async {
    var port = configs[_port];
    var local = configs[_local];
    var type = configs[_type];
    var user = configs[_user];
    var pwd = configs[_pass];

    if (type == 'Data Host') {
      isDataHost = true;
    }

    if (local == null) {
      local = false;
      configs[_local] = local;
    }

    if (type == null) {
      type = "Data Host";
      configs[_type] = type;
    }

    try {
      server = await Server.bind(local, port, user, pwd, this);
    } catch (e) {
      // TODO: Handle failed to start server
    }

    if (type == DataHost) {
      isDataHost = true;
      var nd = provider.getNode('$path/${CreateNode.pathName}');
      if (nd == null) {
        provider.addNode('$path/${CreateNode.pathName}', CreateNode.def());
      }
      nd = provider.getNode('$path/${CreateValue.pathName}');
      if (nd == null) {
        provider.addNode('$path/${CreateValue.pathName}', CreateValue.def());
      }
    }
  }

  @override
  onRemoving() async {
    if (server != null) {
      await server.close();
      server = null;
    }
  }

  Future<String> updateConfig(
      int port, bool local, String type, String user, String pass) async {
    if (pass == null || pass.isEmpty) {
      pass = getConfig(_pass);
    }

    if (server != null) {
      if (server.port == port && server.isLocal == local) {
        server.updateAuth(user, pass);
        return null;
      }

      if (server.port != port) {
        var pOk = Server.checkPort(port);
        if (!pOk) {
          return 'Unable to bind to port: $port';
        }
      }

      await server.close();
    }

    try {
      server = await Server.bind(local, port, user, pass, this);
    } catch (e) {
      return e.toString();
    }

    if (type == DataHost) isDataHost = true;
    return null;
  }

  Future<ServerResponse> getRequest(ServerRequest sr) async {
    if (isDataHost) {
      return _getClient(sr);
    }

    return _getData(sr);
  }

  Future<Null> valueSubscribe(ServerRequest sr, WebSocket socket) async {
    ReqSubscribeListener sub;
    RespSubscribeListener sub2;
    void remoteValueUpdate(ValueUpdate update) {
      if (socket.closeCode != null) {
        sub?.cancel();
        return;
      }

      var isBin = false;
      var value = update.value;
      if (value is ByteData) {
        value = value.buffer.asUint8List(
            value.offsetInBytes,
            value.lengthInBytes
        );
      }

      if (value is Uint8List) {
        isBin = true;
        value = BASE64.encode(value);
      }

      var msg = {
        'value': value,
        'timestamp': update.ts
      };

      if (isBin) msg['bin'] = true;
      socket.add(JSON.encode(msg));
    }

    void hostValueUdate(ValueUpdate update) {
      if (socket.closeCode != null) {
        sub2?.cancel();
        return;
      }

      socket.add(JSON.encode({
        'value': update.value,
        'timestamp': update.ts
      }));
    }

    if (isDataHost) {
      var hostPath = "${this.path}${sr.path}";
      if (hostPath != "/" && hostPath.endsWith("/")) {
        hostPath = hostPath.substring(0, hostPath.length - 1);
      }
      var n = provider.getNode(hostPath);
      sub2 = n.subscribe(hostValueUdate);
    } else {
      sub = link.requester.subscribe(sr.path, remoteValueUpdate);
    }

    socket.done.then((_) {
      sub?.cancel();
      sub2?.cancel();
    });
  }

  Future<ServerResponse> _getClient(ServerRequest sr) async {
    var p = new Path(sr.path);
    if (!p.valid) {
      return new ServerResponse(
          {'error': 'Invalid Path: ${sr.path}'}, ResponseStatus.badRequest);
    }

    RemoteNode nd;
    var requester = link.requester;
    try {
      nd = await requester.getRemoteNode(p.path).timeout(_timeout);
    } catch (e) {
      return new ServerResponse(
          {'error': 'Server error $e'}, ResponseStatus.error);
    }

    if (nd == null) {
      return new ServerResponse(
          {'error': 'Node not found'}, ResponseStatus.notFound);
    }

    var body = await _getRemoteNodeMap(nd, sr);
    return new ServerResponse(body, ResponseStatus.ok);
  }

  Future<ServerResponse> _getData(ServerRequest sr) async {
    var hostPath = "${this.path}${sr.path}";
    if (hostPath != "/" && hostPath.endsWith("/")) {
      hostPath = hostPath.substring(0, hostPath.length - 1);
    }

    // TODO: This
    var n = provider.getNode(hostPath);
  }

  Future<Map> _getRemoteNodeMap(RemoteNode n, ServerRequest req) async {
    if (n == null) {
      return {'error': 'No Such Node'};
    }

    var map = {
      '?name': n.name,
      '?path': req.path,
      '?url': req.request.requestedUri.toString()
    };

    map..addAll(n.configs)..addAll(n.attributes);

    if (map[r'$type'] is String) { // Has a type set, regardles of the value
      var vals = await _getRemoteValues(req.path, req);
      if (vals != null) map.addAll(vals);
    }

    for (String key in n.children.keys) {
      var ch = n.children[key] as RemoteNode;

      var trp = (req.path == '/' ? "" : req.path) + '/$key';
      var m = {
        '?name': ch.name,
        '?path': trp,
        '?url': req.request.requestedUri
            .replace(path: Uri.encodeFull(trp))
            .toString()
      };

      m.addAll(ch.getSimpleMap());

      if (req.childValues && m[r'$type'] is String) {
        var vals = await _getRemoteValues(trp, req);
        if (vals != null) m.addAll(vals);
      }

      map[key] = m;
    }

    return map;
  }

  Future<Map> _getRemoteValues(String path, ServerRequest req) async {
    var c = new Completer<ValueUpdate>();
    ReqSubscribeListener listener;
    listener = link.requester.subscribe(path, (ValueUpdate up) {
      if (!c.isCompleted) {
        c.complete(up);
      }

      if (listener != null) {
        listener.cancel();
        listener = null;
      }
    });

    var val = await c.future.timeout(_timeout, onTimeout: () {
      if (listener != null) {
        listener.cancel();
        listener = null;
      }
      return null;
    });

    if (val == null) return null;

    var value = val.value;
    if (req.returnValue) {
      if (value is ByteData) {
        value = value.buffer.asUint8List(
          value.offsetInBytes,
          value.lengthInBytes
        );
      }

      if (value is Uint8List) {
        value = BASE64.encode(value);
      }
    }

    var map = {
      '?value': value,
      '?value_timestamp': val.ts
    };

    return map;

  }
}
