import '../../design/medic_dialog_controller_scope.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../design/medic_design.dart';

class MedicineStockCard extends StatelessWidget {
  final String medicineId;
  const MedicineStockCard({super.key, required this.medicineId});
  static double? number(Object? v) { final n = v is num ? v.toDouble() : double.tryParse('$v'); return n != null && n.isFinite ? n : null; }
  static String display(num value) => value == value.roundToDouble() ? '${value.toInt()}' : value.toStringAsFixed(1);
  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('medicines').doc(medicineId).snapshots(),
    builder: (context, snap) {
      final data = snap.data?.data() ?? {};
      final remaining = number(data['remainingPills']); final total = number(data['totalPills']);
      final perDose = number(data['pillsPerDose']);
      final valid = remaining != null && total != null && total > 0 && remaining >= 0 && remaining <= total;
      return Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(
        color: MedicColors.forest, borderRadius: BorderRadius.circular(26)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Expanded(child: Text('YOUR MEDICINE STOCK', style: TextStyle(color: MedicColors.mint,
            fontSize: 10, letterSpacing: 1.7, fontWeight: FontWeight.w700))),
            IconButton(onPressed: snap.hasData && !snap.hasError ? () => _edit(context, data) : null,
              tooltip: 'Set medicine stock', icon: const Icon(Icons.edit_outlined, size: 18, color: MedicColors.mint))]),
          Text(valid ? '${display(remaining)} pills left' : snap.hasError ? 'Stock unavailable' : 'Set your pill count',
            style: const TextStyle(fontFamily: 'serif', fontSize: 27, color: Colors.white)),
          const SizedBox(height: 12),
          if (valid) ...[
            TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: remaining / total),
              duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 700),
              builder: (_, value, __) => ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
                value: value, minHeight: 6, color: MedicColors.mint, backgroundColor: Colors.white12))),
            const SizedBox(height: 10),
            Text('${display(total)} total · ${perDose == null ? 'set pills per dose' : '${display(perDose)} per dose'}',
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ] else const Text('Add the actual stock for tablets or capsules. Confirmed doses reduce it automatically.',
            style: TextStyle(fontSize: 12, height: 1.6, color: Colors.white70)),
        ]));
    });

  Future<void> _edit(BuildContext context, Map<String, dynamic> data) async {
    final total = TextEditingController(text: data['totalPills']?.toString() ?? '');
    final remaining = TextEditingController(text: data['remainingPills']?.toString() ?? '');
    final dose = TextEditingController(text: data['pillsPerDose']?.toString() ?? '');
    final form = GlobalKey<FormState>();
    final values = await showDialog<Map<String, double>>(context: context, builder: (context) => MedicDialogControllerScope(controllers: [total, remaining, dose], child: AlertDialog(
      backgroundColor: MedicColors.canvas, title: const Text('Set actual pill stock'),
      content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Use tablets/capsules only. Enter the prescribed quantity per dose; this app does not choose a dosage.',
          style: TextStyle(fontSize: 12, height: 1.5, color: MedicColors.muted)),
        TextFormField(controller: total, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Total pills in this supply'),
          validator: (v) => (number(v) ?? 0) > 0 ? null : 'Enter a positive quantity'),
        TextFormField(controller: remaining, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Pills remaining now'),
          validator: (v) { final n = number(v); final t = number(total.text); return n != null && t != null && n >= 0 && n <= t ? null : 'Enter 0 up to your total'; }),
        TextFormField(controller: dose, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Prescribed pills per dose'),
          validator: (v) => (number(v) ?? 0) > 0 ? null : 'Enter the prescribed quantity'),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, {
          'totalPills': number(total.text)!, 'remainingPills': number(remaining.text)!, 'pillsPerDose': number(dose.text)!,
        }); }, child: const Text('Save stock'))])));
    if (values != null) {
      try {
        await FirebaseFirestore.instance.collection('medicines').doc(medicineId).update({...values, 'stockUpdatedAt': FieldValue.serverTimestamp()});
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock updated.')));
      } catch (_) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock could not be saved. Try again.')));
      }
    }
  }
}
