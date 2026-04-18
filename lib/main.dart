import 'package:flutter/material.dart';
import 'screens/staff_pos_screen.dart';
import 'screens/customer_display_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StaffApp());
}

@pragma('vm:entry-point')
void secondaryDisplayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CustomerDisplayApp());
}

class StaffApp extends StatelessWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StaffPosScreen(),
    );
  }
}

class CustomerDisplayApp extends StatelessWidget {
  const CustomerDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CustomerDisplayScreen(),
    );
  }
}
