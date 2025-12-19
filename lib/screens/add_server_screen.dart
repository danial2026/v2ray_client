import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/v2ray_server.dart';
import '../theme/app_theme.dart';

class AddServerScreen extends StatefulWidget {
  final V2RayServer? server;

  const AddServerScreen({super.key, this.server});

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vmessLinkController = TextEditingController();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _portController = TextEditingController();
  final _uuidController = TextEditingController();
  final _alterIdController = TextEditingController(text: '0');

  bool _showManualForm = false;
  String _network = 'tcp';
  bool _tls = false;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    if (widget.server != null) {
      final s = widget.server!;
      _nameController.text = s.name;
      _addressController.text = s.address;
      _portController.text = s.port.toString();
      _uuidController.text = s.uuid;
      _alterIdController.text = s.alterId.toString();
      _network = s.network;
      _tls = s.tls == 'tls';
      _showManualForm = true;
    }
  }

  @override
  void dispose() {
    _vmessLinkController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _portController.dispose();
    _uuidController.dispose();
    _alterIdController.dispose();
    super.dispose();
  }

  void _importFromLink() {
    setState(() {
      _parseError = null;
    });

    final link = _vmessLinkController.text.trim();
    if (link.isEmpty) {
      setState(() => _parseError = 'Please paste a link');
      return;
    }

    try {
      final server = V2RayServer.fromAnyLink(link);
      Navigator.pop(context, server);
    } catch (e) {
      setState(() {
        _parseError = e.toString().contains('Invalid') ? 'Invalid or unsupported link format' : 'Error: ${e.toString()}';
      });
    }
  }

  void _saveManualServer() {
    if (_formKey.currentState!.validate()) {
      final server = V2RayServer(
        id: widget.server?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        port: int.parse(_portController.text.trim()),
        uuid: _uuidController.text.trim(),
        protocol: widget.server?.protocol ?? 'vmess',
        alterId: int.tryParse(_alterIdController.text.trim()) ?? 0,
        network: _network,
        tls: _tls ? 'tls' : 'none',
        encryption: widget.server?.encryption,
        flow: widget.server?.flow,
      );

      Navigator.pop(context, server);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.server != null ? 'EDIT CONFIG' : 'NEW CONFIG')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_showManualForm) ...[
                Text(
                  'LINK DECODER',
                  style: TextStyle(fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _vmessLinkController,
                  decoration: const InputDecoration(labelText: 'VMESS / VLESS Link', hintText: 'Paste configuration link here'),
                  maxLines: 4,
                ),
                if (_parseError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _parseError!,
                      style: const TextStyle(color: AppTheme.errorColor, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: _importFromLink, child: const Text('AUTO IMPORT')),
                ),
                const SizedBox(height: 32),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _showManualForm = true),
                    child: Text(
                      'MANUAL CONFIGURATION',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
              ] else
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CORE PARAMETERS',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w900,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Connection Name'),
                        validator: (value) => (value == null || value.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _addressController,
                              decoration: const InputDecoration(labelText: 'Address'),
                              validator: (value) => (value == null || value.isEmpty) ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: _portController,
                              decoration: const InputDecoration(labelText: 'Port'),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) return '??';
                                final port = int.tryParse(value);
                                if (port == null || port < 1 || port > 65535) return '!';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _uuidController,
                        decoration: const InputDecoration(labelText: 'Universal Unique ID'),
                        validator: (value) => (value == null || value.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TRANSPORT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: _network,
                                  items: ['tcp', 'ws', 'grpc']
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e.toUpperCase(), style: const TextStyle(fontSize: 13, letterSpacing: 1)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => setState(() => _network = v!),
                                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TLS',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Switch(
                                value: _tls,
                                onChanged: (v) => setState(() => _tls = v),
                                activeTrackColor: Colors.white12,
                                activeThumbColor: Colors.white,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 48),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(onPressed: _saveManualServer, child: const Text('SAVE CONFIGURATION')),
                      ),
                      if (widget.server == null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: TextButton(
                              onPressed: () => setState(() => _showManualForm = false),
                              child: Text(
                                'BACK TO DECODER',
                                style: TextStyle(fontSize: 11, letterSpacing: 1, color: Colors.white.withValues(alpha: 0.3)),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
