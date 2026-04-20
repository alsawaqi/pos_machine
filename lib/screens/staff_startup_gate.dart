import 'package:flutter/material.dart';

import '../services/local_storage_service.dart';
import 'staff_pos_screen.dart';
import 'terminal_setup_screen.dart';

class StaffStartupGate extends StatefulWidget {
  const StaffStartupGate({super.key});

  @override
  State<StaffStartupGate> createState() => _StaffStartupGateState();
}

class _StaffStartupGateState extends State<StaffStartupGate> {
  bool _loading = true;
  String? _terminalId;

  @override
  void initState() {
    super.initState();
    _restoreTerminalId();
  }

  Future<void> _restoreTerminalId() async {
    final terminalId = await LocalStorageService.getTerminalId();
    if (!mounted) return;
    setState(() {
      _terminalId = terminalId?.trim();
      _loading = false;
    });
  }

  void _handleTerminalSaved(String terminalId) {
    setState(() {
      _terminalId = terminalId.trim();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF102028),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_terminalId == null || _terminalId!.isEmpty) {
      return TerminalSetupScreen(onSaved: _handleTerminalSaved);
    }

    return const StaffPosScreen();
  }
}
