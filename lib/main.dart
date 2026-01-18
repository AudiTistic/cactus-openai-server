import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() {
  runApp(const OpenAIProxyApp());
}

class OpenAIProxyApp extends StatelessWidget {
  const OpenAIProxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenAI Proxy Server',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ServerScreen(),
    );
  }
}

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  HttpServer? _server;
  bool _isRunning = false;
  final int _port = 8080;
  String _backendUrl = 'https://api.openai.com';
  String _apiKey = '';
  final TextEditingController _backendController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _backendController.text = _backendUrl;
  }

  @override
  void dispose() {
    _stopServer();
    _backendController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _startServer() async {
    if (_isRunning) return;

    try {
      final handler = const shelf.Pipeline()
          .addMiddleware(shelf.logRequests())
          .addHandler(_handleRequest);

      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
      setState(() {
        _isRunning = true;
        _backendUrl = _backendController.text;
        _apiKey = _apiKeyController.text;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting server: $e')),
        );
      }
    }
  }

  Future<void> _stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      setState(() {
        _isRunning = false;
      });
    }
  }

  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    try {
      if (!request.url.path.startsWith('v1/')) {
        return shelf.Response.notFound('Not Found');
      }

      final backendUri = Uri.parse('$_backendUrl/${request.url.path}');
      final body = await request.readAsString();
      
      final headers = {
        'Content-Type': 'application/json',
        if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
      };

      http.Response backendResponse;
      
      if (request.method == 'GET') {
        backendResponse = await http.get(backendUri, headers: headers);
      } else if (request.method == 'POST') {
        backendResponse = await http.post(
          backendUri,
          headers: headers,
          body: body,
        );
      } else {
        return shelf.Response(405, body: 'Method Not Allowed');
      }

      return shelf.Response(
        backendResponse.statusCode,
        body: backendResponse.body,
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return shelf.Response.internalServerError(
        body: json.encode({'error': e.toString()}),
      );
    }
  }

  String? _getLocalIP() {
    try {
      final interfaces = NetworkInterface.listSync(
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final localIP = _getLocalIP();
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('OpenAI Proxy Server'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _backendController,
              decoration: const InputDecoration(
                labelText: 'Backend URL',
                hintText: 'https://api.openai.com',
                border: OutlineInputBorder(),
              ),
              enabled: !_isRunning,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key (optional)',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              enabled: !_isRunning,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isRunning ? _stopServer : _startServer,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                _isRunning ? 'Stop Server' : 'Start Server',
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 24),
            if (_isRunning)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Server Running',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (localIP != null)
                        Text('Local IP: $localIP:$_port'),
                      if (localIP != null) const SizedBox(height: 8),
                      Text('Localhost: http://localhost:$_port'),
                      const SizedBox(height: 8),
                      Text('Backend: $_backendUrl'),
                      const SizedBox(height: 16),
                      const Text(
                        'Endpoints:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text('• POST /v1/chat/completions'),
                      const Text('• GET  /v1/models'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
