import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cactus/cactus.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CactusOpenAIApp());
}

class CactusOpenAIApp extends StatelessWidget {
  const CactusOpenAIApp({super.key});

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
  CactusLM? _cactusLM;
  bool _isRunning = false;
  bool _isModelLoaded = false;
  final int _port = 8080;
  String _modelSlug = 'qwen3-0.6';
  String _status = 'Stopped';
  final TextEditingController _modelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _modelController.text = _modelSlug;
  }

  @override
  void dispose() {
    _stopServer();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _initializeModel() async {
    setState(() => _status = 'Initializing Cactus AI...');
    
    try {
      _cactusLM = CactusLM();
      setState(() => _status = 'Downloading model $_modelSlug...');
      
      await _cactusLM!.downloadModel(slug: _modelSlug);
      
      setState(() => _status = 'Loading model...');
      await _cactusLM!.initializeModel(CactusInitParams(model: _modelSlug));      await _cactusLM!.downloadModel(model: _modelSlug);        _status = 'Model loaded: $_modelSlug';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing model: $e')),
        );
      }
    }
  }

  Future<void> _startServer() async {
    if (_isRunning) return;

    setState(() => _status = 'Starting server...');
    
    // Initialize model if not loaded
    if (!_isModelLoaded) {
      await _initializeModel();
      if (!_isModelLoaded) {
        setState(() => _status = 'Failed to load model');
        return;
      }
    }

    try {
      final handler = const shelf.Pipeline()
          .addMiddleware(shelf.logRequests())
          .addHandler(_handleRequest);

      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
      setState(() {
        _isRunning = true;
        _modelSlug = _modelController.text;
        _status = 'Server running on 0.0.0.0:$_port';
      });
    } catch (e) {
      setState(() => _status = 'Error starting server: $e');
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
        _status = 'Server stopped';
      });
    }
  }

  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    try {
      // Parse incoming OpenAI-compatible request
      final body = await request.readAsString();
      final Map<String, dynamic> requestData = json.decode(body);

      // Handle /v1/chat/completions
      if (request.url.path == 'v1/chat/completions') {
        final messages = requestData['messages'] as List<dynamic>?;
        if (messages == null || messages.isEmpty) {
          return shelf.Response(400, 
            body: json.encode({'error': 'messages field is required'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Convert OpenAI messages to Cactus format
        final cactusMessages = messages.map((msg) => ChatMessage(
          content: msg['content'] as String,
          role: msg['role'] as String,
        )).toList();

        // Call Cactus AI
        final result = await _cactusLM!.generateCompletion(
          messages: cactusMessages,
          params: CactusCompletionParams(
            maxTokens: requestData['max_tokens'] as int? ?? 512,
            temperature: (requestData['temperature'] as num?)?.toDouble() ?? 0.7,
          ),
        );

        if (!result.success) {
          return shelf.Response.internalServerError(
            body: json.encode({'error': result.response}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Return OpenAI-compatible response
        final response = {
          'id': 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
          'object': 'chat.completion',
          'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'model': _modelSlug,
          'choices': [{
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': result.response,
            },
            'finish_reason': 'stop',
          }],
          'usage': {
            'prompt_tokens': 0,
            'completion_tokens': 0,
            'total_tokens': 0,
          },
        };

        return shelf.Response.ok(
          json.encode(response),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Handle /v1/models
      if (request.url.path == 'v1/models' && request.method == 'GET') {
        final response = {
          'object': 'list',
          'data': [{
            'id': _modelSlug,
            'object': 'model',
            'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'owned_by': 'cactus-ai',
          }],
        };

        return shelf.Response.ok(
          json.encode(response),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return shelf.Response.notFound('Not Found');
    } catch (e) {
      return shelf.Response.internalServerError(
        body: json.encode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
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
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Model Slug',
                hintText: 'qwen3-0.6, gemma3-270m',
                border: OutlineInputBorder(),
              ),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status: $_status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isRunning ? Colors.green : Colors.grey,
                      ),
                    ),
            if (_isRunning)                      const SizedBox(height: 16),
                      const Text('Listening: 0.0.0.0:8080'),
                      const SizedBox(height: 8),
                      Text('Model: $_modelSlug'),
                      const SizedBox(height: 16),
                      const Text(
                        'OpenAI-Compatible Endpoints:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text('• POST /v1/chat/completions'),
                      const Text('• GET  /v1/models'),
                    ],
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
