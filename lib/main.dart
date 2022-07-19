import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:socket_io_client/socket_io_client.dart';
import 'package:http/http.dart';

enum RemoteState { disconnected, connected }

enum ClickType { single, double, right }

const DEBUG = false;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    return MaterialApp(
      title: 'Air Control',
      // change the notification theme to light mode
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      home: const MainPage(title: 'Air Control'),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  String? _ip;
  RemoteState? _status;
  Socket? _socket;
  int _volume = 50;

  @override
  void initState() {
    /**
     * make get request to 192.168.1.[0-10]/home
     * if it returns working then put the ip address in the ip variable
     */
    figureOutIp();
    super.initState();
  }

  void log(String message) {
    if (DEBUG) {
      print(message);
    }
  }

  void figureOutIp() {
    Future.delayed(const Duration(seconds: 1), () async {
      for (int i = 2; i < 10; i++) {
        try {
          final response =
              await get(Uri.parse('http://192.168.1.$i:9999/home'));
          if (response.statusCode == 200) {
            setState(() {
              _ip = 'http://192.168.1.$i:9999';
            });
            log('Hey, we got connected at $_ip');
            connectToSocket();
            break;
          }
        } catch (e) {
          log('can\'t connect to http://192.168.1.$i:9999');
          continue;
        }
      }
    });
  }

  void connectToSocket() {
    _socket = io(_ip, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    _socket?.connect();
    _socket?.on('connect', (_) {
      log('Connected to socket');
      // make a breadcrumb to say we connected
      setState(() {
        _status = RemoteState.connected;
      });
    });
    _socket?.on('disconnect', (_) {
      log('Disconnected from socket');
      setState(() {
        _status = RemoteState.disconnected;
      });
    });
  }

  void streamMouse(double x, double y) {
    _socket?.emit('mouseMove', {'x': x, 'y': y});
  }

  void streamTouch(ClickType clickType) {
    log('streamTouch $clickType');
    _socket?.emit('mouseClick', {'clickType': clickType.index});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 20, left: 20),
            child: Text("Volume"),
          ),
          Slider(
            value: _volume.toDouble(),
            min: 0,
            max: 100,
            divisions: 20,
            onChanged: (double value) {
              setState(() {
                _volume = value.toInt();
              });
              _socket?.emit('volume', {'volume': _volume});
            },
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => streamTouch(ClickType.single),
              onDoubleTap: () => streamTouch(ClickType.double),
              onLongPress: () => streamTouch(ClickType.right),
              onPanUpdate: (DragUpdateDetails details) =>
                  streamMouse(details.delta.dx, details.delta.dy),
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: const InkWell(child: Center(child: Text('Touch Pad'))),
              ),
            ),
          ),
          // a text field and a send icon button to send keystrokes to the server
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      border: UnderlineInputBorder(),
                      labelText: 'Keystroke',
                    ),
                    onSubmitted: (String text) {
                      _socket?.emit('keystroke', {'keystroke': text});
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    _socket?.emit('keystroke', {'keystroke': 'Enter'});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
