import 'package:flutter/material.dart';
import 'package:flutter_presentation_display/flutter_presentation_display.dart';
import '../models/pos_models.dart';

class CustomerDisplayScreen extends StatefulWidget {
  const CustomerDisplayScreen({super.key});

  @override
  State<CustomerDisplayScreen> createState() => _CustomerDisplayScreenState();
}

class _CustomerDisplayScreenState extends State<CustomerDisplayScreen> {
  final FlutterPresentationDisplay _display = FlutterPresentationDisplay();
  OrderSnapshot order = OrderSnapshot.initial();

  @override
  void initState() {
    super.initState();

    _display.listenDataFromMainDisplay((dynamic data) {
      if (data is Map && data['type'] == 'order_snapshot') {
        setState(() {
          order = OrderSnapshot.fromMap(Map<String, dynamic>.from(data));
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MITHQAL 2.0',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text(order.paymentStatus, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: order.items.length,
                itemBuilder: (context, index) {
                  final item = order.items[index];
                  return ListTile(
                    title: Text(item['name'].toString()),
                    subtitle: Text('Qty: ${item['qty']}'),
                    trailing: Text(
                      '${(item['lineTotal'] as num).toDouble().toStringAsFixed(3)} OMR',
                    ),
                  );
                },
              ),
            ),
            Text('Subtotal: ${order.subtotal.toStringAsFixed(3)} OMR'),
            Text('Tax: ${order.tax.toStringAsFixed(3)} OMR'),
            Text(
              'Total: ${order.total.toStringAsFixed(3)} OMR',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
