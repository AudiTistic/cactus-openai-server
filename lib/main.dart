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
  String _deviceIP = 'Detecting...';
  bool _useCustomModel = false;
  
  final TextEditingController _customModelController = TextEditingController();
  
  // Common Cactus AI models
  final List<String> _commonModels = [
    'qwen3-0.6',
    'qwen3-1.7',
    'gemma3-270m',
    'phi4-3.8',
    'llama3.2-1',
    'llama3.2-3',
  ];

  @override
  void initState() {
    super.initState();
    _detectIP();
  }

  @override
  void dispose() {
    _stopServer();
    _customModelController.dispose();
    super.dispose();
  }

  Future<void> _detectIP() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          // Get the first non-loopback IPv4 address
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            setState(() => _deviceIP = addr.address);
            return;
          }
        }
      }
      setState(() => _deviceIP = '0.0.0.0');
    } catch (e) {
      setState(() => _deviceIP = 'Unknown');
    }
  }

  Future<void> _initializeModel() async {
    setState(() => _status = 'Initializing Cactus AI...');
    
    try {
      _cactusLM = CactusLM();
      
      final modelToLoad = _useCustomModel 
          ? _customModelController.text.trim()
          : _modelSlug;
      
      setState(() => _status = 'Downloading model $modelToLoad...');
      
      // Support both slug and HF URLs
      if (modelToLoad.startsWith('http')) {
        await _cactusLM!.downloadModel(model: modelToLoad);
      } else {
        await _cactusLM!.downloadModel(model: modelToLoad);
      }
      
      setState(() => _status = 'Loading model...');
      await _cactusLM!.initializeModel();
      
      setState(() {
        _isModelLoaded = true;
        _status = 'Model loaded: $modelToLoad';
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
        _status = 'Server running on $_deviceIP:$_port';
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
      
      // Handle empty body
      if (body.isEmpty) {
        return shelf.Response(400, 
          body: json.encode({'error': 'Request body is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      
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
          'model': _useCustomModel ? _customModelController.text : _modelSlug,
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
            'id': _useCustomModel ? _customModelController.text : _modelSlug,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Model Selection
            Row(
              children: [
                Checkbox(
                  value: !_useCustomModel,
                  onChanged: _isRunning ? null : (val) {
                    setState(() => _useCustomModel = !val!);
                  },
                ),
                const Text('Use preset model'),
              ],
            ),
            if (!_useCustomModel)
              DropdownButtonFormField<String>(
                value: _modelSlug,
                decoration: const InputDecoration(
                  labelText: 'Select Model',
                  border: OutlineInputBorder(),
                ),
                items: _commonModels.map((model) => DropdownMenuItem(
                  value: model,
                  child: Text(model),
                )).toList(),
                onChanged: _isRunning ? null : (value) {
                  if (value != null) {
                    setState(() => _modelSlug = value);
                  }
                },
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _useCustomModel,
                  onChanged: _isRunning ? null : (val) {
                    setState(() => _useCustomModel = val!);
                  },
                ),
                const Text('Use custom model/HF URL'),
              ],
            ),
            if (_useCustomModel)
              TextField(
                controller: _customModelController,
                decoration: const InputDecoration(
                  labelText: 'Model slug or Hugging Face URL',
                  hintText: 'qwen3-1.7 or https://huggingface.co/...',
                  border: OutlineInputBorder(),
                ),
                enabled: !_isRunning,
                maxLines: 2,
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
                    const SizedBox(height: 16),
                    Text('Device IP: $_deviceIP',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    if (_isRunning) ...[
                      const SizedBox(height: 8),
                      Text('Port: $_port'),
                      const SizedBox(height: 8),
                      SelectableText(
                        'Base URL: http://$_deviceIP:$_port',
                        style: const TextStyle(fontFamily: 'monospace', color: Colors.blue),
                      ),
                      const SizedBox(height: 8),
                      Text('Model: ${_useCustomModel ? _customModelController.text : _modelSlug}'),
                      const SizedBox(height: 16),
                      const Text(
                        'OpenAI-Compatible Endpoints:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text('• POST /v1/chat/completions'),
                      const Text('• GET /v1/models'),
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
