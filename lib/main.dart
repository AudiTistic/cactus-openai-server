import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cactus/cactus.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:network_info_plus/network_info_plus.dart';

void main() {
  runApp(const CactusOpenAIServerApp());
}

class CactusOpenAIServerApp extends StatelessWidget {
  const CactusOpenAIServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cactus OpenAI Server',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
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
  String _ipAddress = 'Loading...';
  final int _port = 8080;
  String _logs = '';
  CactusLM? _cactusLM;
  bool _modelLoaded = false;

  @override
  void initState() {
    super.initState();
    _initializeServer();
  }

  Future<void> _initializeServer() async {
    // Get IP address
    final info = NetworkInfo();
    final wifiIP = await info.getWifiIP();
    setState(() {
      _ipAddress = wifiIP ?? 'Unknown';
    });

    // Initialize Cactus
    _addLog('Initializing Cactus engine...');
    try {
      _cactusLM = CactusLM();
      // Note: You'll need to configure telemetry token in production
      // CactusConfig.isTelemetryEnabled = true;
      _modelLoaded = true;
      _addLog('Cactus engine ready');
    } catch (e) {
      _addLog('Cactus init error: $e');
    }
  }

  void _addLog(String message) {
    setState(() {
      _logs = '${DateTime.now().toString().substring(11, 19)}: $message\\n$_logs';
    });
  }

  Future<void> _startServer() async {
    if (!_modelLoaded) {
      _addLog('ERROR: Cactus not initialized');
      return;
    }

    try {
      _server = await shelf_io.serve(
        _handleRequest,
        InternetAddress.anyIPv4,
        _port,
      );
      setState(() {
        _isRunning = true;
      });
      _addLog('Server started on $_ipAddress:$_port');
    } catch (e) {
      _addLog('Server start error: $e');
    }
  }

  Future<void> _stopServer() async {
    await _server?.close(force: true);
    setState(() {
      _isRunning = false;
    });
    _addLog('Server stopped');
  }

  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    _addLog('${request.method} ${request.url.path}');

    // CORS headers
    final headers = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Content-Type': 'application/json',
    };

    if (request.method == 'OPTIONS') {
      return shelf.Response.ok('', headers: headers);
    }

    // Health check
    if (request.method == 'GET' && request.url.path == '') {
      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'engine': 'cactus'}),
        headers: headers,
      );
    }

    // OpenAI chat completions endpoint
    if (request.method == 'POST' && request.url.path == 'v1/chat/completions') {
      try {
        final body = await request.readAsString();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        
        final messages = payload['messages'] as List<dynamic>?;
        if (messages == null || messages.isEmpty) {
          return shelf.Response(400,
              body: jsonEncode({'error': 'messages required'}),
              headers: headers);
        }

        // Build prompt from messages
        final prompt = _buildPrompt(messages.cast<Map<String, dynamic>>());
        
        // Generate with Cactus
        final result = await _cactusLM!.generateCompletion(
          input: prompt,
          maxTokens: (payload['max_tokens'] as int?) ?? 256,
          temperature: ((payload['temperature'] as num?) ?? 0.7).toDouble(),
        );

        // OpenAI-compatible response
        final response = {
          'id': 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
          'object': 'chat.completion',
          'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'model': payload['model'] ?? 'cactus-default',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': result.text,
              },
              'finish_reason': 'stop',
            }
          ],
          'usage': {
            'prompt_tokens': prompt.length ~/ 4,
            'completion_tokens': result.text.length ~/ 4,
            'total_tokens': (prompt.length + result.text.length) ~/ 4,
          }
        };

        _addLog('Completed: ${result.text.substring(0, result.text.length > 30 ? 30 : result.text.length)}...');
        return shelf.Response.ok(jsonEncode(response), headers: headers);
      } catch (e) {
        _addLog('Error: $e');
        return shelf.Response(500,
            body: jsonEncode({'error': e.toString()}),
            headers: headers);
      }
    }

    // Models list endpoint
    if (request.method == 'GET' && request.url.path == 'v1/models') {
      return shelf.Response.ok(
        jsonEncode({
          'object': 'list',
          'data': [
            {'id': 'cactus-default', 'object': 'model', 'owned_by': 'cactus'}
          ]
        }),
        headers: headers,
      );
    }

    return shelf.Response.notFound(
      jsonEncode({'error': 'Not found'}),
      headers: headers,
    );
  }

  String _buildPrompt(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] as String?;
      final content = msg['content'] as String?;
      if (role == 'system') {
        buffer.writeln('System: $content');
      } else if (role == 'user') {
        buffer.writeln('User: $content');
      } else if (role == 'assistant') {
        buffer.writeln('Assistant: $content');
      }
    }
    buffer.write('Assistant: ');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Cactus OpenAI Server'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      _isRunning ? 'Server Running' : 'Server Stopped',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'http://$_ipAddress:$_port/v1/chat/completions',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _modelLoaded
                          ? (_isRunning ? _stopServer : _startServer)
                          : null,
                      child: Text(_isRunning ? 'Stop Server' : 'Start Server'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Logs:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _logs.isEmpty ? 'No logs yet' : _logs,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }
}
