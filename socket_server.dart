// SocketServer added ;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// import 'package:public_ip_address/public_ip_address.dart';

import 'package:http/http.dart' as http;

import 'package:primo_pay/main.dart';
//import 'package:shared_preferences/shared_preferences.dart';

//SocketServerState pageState;

class SocketServer extends ConsumerStatefulWidget {
  @override
  _SocketServerState createState() => _SocketServerState();
}

class _SocketServerState extends ConsumerState<SocketServer> {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  List<MessageItem> items = [];

  String localIP = "";

  ServerSocket? serverSocket;
  Socket? clientSocket;
  int port = 8000;

  late TextEditingController msgCon; // Declare without initializing

  void initState() {
    super.initState();
    getPublicIP();
    // getIP();
    //WidgetsBinding.instance.addPostFrameCallback((_) {
    //  startServer();
    //});
  }

  @override
  void dispose() {
    if (clientSocket != null) {
      print("disconnectFromClient");
      clientSocket?.close();
      serverSocket?.close();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize msgCon here because it depends on Provider
    //if (msgCon == null) { // This check ensures msgCon is initialized only once
    msgCon = TextEditingController(text: ref.watch(linkProvider));
    //}
  }

  @override
  Widget build(BuildContext context) {
    // getIP();

    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(title: Text("Socket Server")),
      body: Column(
        children: <Widget>[
          ipInfoArea(),
          messageListArea(),
          submitArea(),
        ],
      ),
    );
  }

  Widget ipInfoArea() {
    return Card(
      child: ListTile(
        dense: true,
        leading: Text("IP"),
        title: Text(localIP),
        trailing: ElevatedButton(
          child: Text((serverSocket == null) ? "Start" : "Stop"),
          onPressed: (serverSocket == null) ? startServer : stopServer,
        ),
      ),
    );
  }

  Widget messageListArea() {
    return Expanded(
      child: ListView.builder(
          reverse: true,
          itemCount: items.length,
          itemBuilder: (context, index) {
            MessageItem item = items[index];
            return Container(
              alignment: (item.owner == localIP)
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: (item.owner == localIP)
                        ? Colors.blue[100]
                        : Colors.grey[200]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      (item.owner == localIP) ? "Server" : "Client",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      item.content,
                      style: TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
            );
          }),
    );
  }

  Widget submitArea() {
    return Card(
      child: ListTile(
        title: TextField(
          controller: msgCon,
        ),
        trailing: IconButton(
          icon: Icon(Icons.send),
          color: Colors.blue,
          disabledColor: Colors.grey,
          onPressed: (clientSocket != null) ? submitMessage : null,
        ),
      ),
    );
  }

  Future<void> getPublicIP() async {
    try {
      final response =
          await http.get(Uri.parse('https://api.ipify.org?format=json'));
      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);
        setState(() {
          localIP = jsonResponse['ip'];
          print(localIP);
        });
      } else {
        throw Exception('Failed to get public IP address');
      }
    } catch (e) {
      print('Failed to get public IP address: $e');
    }
  }

  void startServer() async {
    print(serverSocket);
    serverSocket =
        await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
    print(serverSocket);
    serverSocket?.listen(handleClient);
  }

  void handleClient(Socket client) {
    clientSocket = client;

    showSnackBarWithKey(
        "A new client has connected from ${clientSocket?.remoteAddress.address}:${clientSocket?.remotePort}");

    clientSocket?.listen(
      (onData) {
        String message = String.fromCharCodes(onData).trim();
        print("Received message: $message");

        // Regex to match the ECR request message format
        final requestPattern = RegExp(r'^(\d{8})(0)(s)$');

        // Check if the incoming message matches the ECR request format
        if (requestPattern.hasMatch(message)) {
          final match = requestPattern.firstMatch(message);

          if (match != null) {
            final terminalId = match.group(1)!;
            final reserved = match.group(2)!;
            final messageCode = match.group(3)!;

            // Get current date and time
            final now = DateTime.now().toUtc();
            final formattedDateTime =
                '${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year.toString().substring(2)}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}'; // DDMMAAOOMM
            final terminalStatus = '2'; // Hardcoded terminal status
            final softwareVersions =
                'SYS03.4ESSA05.5CMST08.55EMV08.81ECR01.55'; // Hardcoded software versions

            final responseMessage =
                '$terminalId$reserved$messageCode${'0' * 10}$formattedDateTime$terminalStatus$softwareVersions';

            // Send the constructed response message back to the client
            sendMessage(responseMessage);
          }
        } else {
          print("Pattern not detected");
        }
        setState(() {
          items.insert(
              0, MessageItem(clientSocket!.remoteAddress.address, message));
        });
      },
      onError: (e) {
        showSnackBarWithKey(e.toString());
        disconnectClient();
      },
      onDone: () {
        showSnackBarWithKey("Connection has terminated.");
        disconnectClient();
      },
    );
  }

  void stopServer() {
    disconnectClient();
    serverSocket?.close();
    setState(() {
      serverSocket = null;
    });
  }

  bool _isActive = true;

  void disconnectClient() {
    print("disconnect From Client");
    clientSocket?.close();

    if (_isActive) {
      setState(() {
        clientSocket = null;
      });
    }
  }

  void submitMessage() {
    if (msgCon.text.isEmpty) return;
    setState(() {
      items.insert(0, MessageItem(localIP, msgCon.text));
    });
    sendMessage(msgCon.text);
    msgCon.clear();
  }

  void sendMessage(String message) {
    clientSocket?.write("$message\n");
  }

  showSnackBarWithKey(String message) {
    ScaffoldMessenger.of(scaffoldKey.currentContext!)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Done',
          onPressed: () {},
        ),
      ));
  }
}

class MessageItem {
  String owner;
  String content;

  MessageItem(this.owner, this.content);
}



// So echo the terminal id, 0,s, 0, date time, then i would say 2, then you might hardcode ecr01.55

// tcp_socket_connection: ^0.3.1
// public_ip_address: ^1.2.0
// http: 1.2.0
