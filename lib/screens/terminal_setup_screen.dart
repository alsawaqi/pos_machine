import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/local_storage_service.dart';

class TerminalSetupScreen extends StatefulWidget {
  final ValueChanged<String> onSaved;

  const TerminalSetupScreen({super.key, required this.onSaved});

  @override
  State<TerminalSetupScreen> createState() => _TerminalSetupScreenState();
}

class _TerminalSetupScreenState extends State<TerminalSetupScreen> {
  final TextEditingController _terminalIdController = TextEditingController();
  String? _terminalIdError;
  String? _saveError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSavedTerminalId();
  }

  @override
  void dispose() {
    _terminalIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedTerminalId() async {
    final terminalId = await LocalStorageService.getTerminalId();
    if (!mounted || terminalId == null || terminalId.isEmpty) return;
    _terminalIdController.text = terminalId;
  }

  Future<void> _saveTerminalId() async {
    final terminalId = _terminalIdController.text.trim();

    setState(() {
      _terminalIdError = null;
      _saveError = null;
    });

    if (terminalId.isEmpty) {
      setState(() {
        _terminalIdError = 'Please enter the terminal ID.';
      });
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await LocalStorageService.saveTerminalId(terminalId);
      if (!mounted) return;
      widget.onSaved(terminalId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Failed to save the terminal ID: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B22),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0D1B22),
                    Color(0xFF15303A),
                    Color(0xFF1F4A57),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: -80,
            child: _GlowBlob(
              size: 340,
              color: const Color(0x6654A9B0),
            ),
          ),
          Positioned(
            right: -100,
            bottom: -120,
            child: _GlowBlob(
              size: 420,
              color: const Color(0x444AA8C0),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(34),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(34),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.24),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 30,
                              offset: Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Connect This POS Terminal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Enter the terminal ID before the staff POS is unlocked. This value is saved locally and used for Payment Terminaly payment requests.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.80),
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _terminalIdController,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) {
                                if (!_saving) {
                                  _saveTerminalId();
                                }
                              },
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Terminal ID',
                                hintText: 'Enter the payment terminal ID',
                                errorText: _terminalIdError,
                                labelStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                ),
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.42),
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.10),
                                prefixIcon: const Icon(
                                  Icons.point_of_sale_rounded,
                                  color: Colors.white,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.16),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF8EDCE6),
                                    width: 1.4,
                                  ),
                                ),
                              ),
                            ),
                            if (_saveError != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _saveError!,
                                style: const TextStyle(
                                  color: Color(0xFFFFA8A8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _saving ? null : _saveTerminalId,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0B6D8A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                ),
                                child: _saving
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Text(
                                        'Continue To POS',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 180, spreadRadius: 50),
          ],
        ),
      ),
    );
  }
}
