import 'package:flutter/material.dart';

class BarcodeScannerSimulatorDialog extends StatefulWidget {
  final Function(String)? onBarcodeScanned;
  final Function(String)? onScanned;
  final Function(String)? onScan;
  final Function(String)? onBarcodeSelected;

  const BarcodeScannerSimulatorDialog({
    super.key,
    this.onBarcodeScanned,
    this.onScanned,
    this.onScan,
    this.onBarcodeSelected,
  });

  @override
  State<BarcodeScannerSimulatorDialog> createState() =>
      _BarcodeScannerSimulatorDialogState();
}

class _BarcodeScannerSimulatorDialogState
    extends State<BarcodeScannerSimulatorDialog> {
  final TextEditingController _customBarcodeController =
      TextEditingController();

  final List<Map<String, String>> _sampleBarcodes = const [
    {
      'name': 'Aashirvaad Atta 5kg',
      'barcode': '8901030383709',
    },
    {
      'name': 'Amul Taaza Milk 1L',
      'barcode': '8901262010054',
    },
    {
      'name': 'Fortune Sunflower Oil 1L',
      'barcode': '8901063142274',
    },
    {
      'name': 'Maggi Masala Noodles',
      'barcode': '8901058852355',
    },
    {
      'name': 'Tata Salt 1kg',
      'barcode': '8901030775313',
    },
  ];

  void _triggerScan(String barcode) {
    Navigator.pop(context);
    if (widget.onBarcodeScanned != null) {
      widget.onBarcodeScanned!(barcode);
    } else if (widget.onScanned != null) {
      widget.onScanned!(barcode);
    } else if (widget.onScan != null) {
      widget.onScan!(barcode);
    } else if (widget.onBarcodeSelected != null) {
      widget.onBarcodeSelected!(barcode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.qr_code_scanner, color: Color(0xFF2563EB)),
                    SizedBox(width: 8),
                    Text(
                      'Barcode Scanner',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Select a sample barcode or enter manual digits:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customBarcodeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter 13-digit EAN Barcode',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check_circle, color: Color(0xFF16A34A)),
                  onPressed: () {
                    final b = _customBarcodeController.text.trim();
                    if (b.isNotEmpty) _triggerScan(b);
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sample FMCG Barcodes:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 6),
            ..._sampleBarcodes.map((item) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(item['name']!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text(item['barcode']!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () => _triggerScan(item['barcode']!),
              );
            }),
          ],
        ),
      ),
    );
  }
}
