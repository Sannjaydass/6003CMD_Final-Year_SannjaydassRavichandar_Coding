import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../../design/medic_design.dart';
import '../../services/medicine_photo_service.dart';

class MedicinePhoto extends StatefulWidget {
  final String? path;
  final double size;
  final bool expandable;
  const MedicinePhoto({super.key, this.path, this.size = 64, this.expandable = false});
  @override
  State<MedicinePhoto> createState() => _MedicinePhotoState();
}
class _MedicinePhotoState extends State<MedicinePhoto> {
  Future<Uint8List?>? _bytes;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(covariant MedicinePhoto old) {
    super.didUpdateWidget(old); if (old.path != widget.path) _load();
  }
  void _load() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final path = widget.path;
    _bytes = path != null && uid != null && path.startsWith('medicine_photos/$uid/')
        ? FirebaseStorage.instance.ref(path).getData(MedicinePhotoService.maxBytes).timeout(const Duration(seconds: 15)) : null;
  }
  Widget _placeholder({bool error = false}) => Center(child: Icon(
    error ? Icons.broken_image_outlined : Icons.medication_rounded, color: MedicColors.green, size: 26));
  @override
  Widget build(BuildContext context) => ClipRRect(borderRadius: BorderRadius.circular(20),
    child: Container(width: widget.size, height: widget.size, color: MedicColors.mint.withOpacity(.3),
      child: _bytes == null ? _placeholder() : FutureBuilder<Uint8List?>(future: _bytes, builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: MedicColors.green)));
        if (snap.hasError || snap.data == null) return InkWell(onTap: () => setState(_load), child: _placeholder(error: true));
        final bytes = snap.data!;
        return InkWell(onTap: !widget.expandable ? null : () => showDialog<void>(context: context, builder: (context) => Dialog(
          backgroundColor: MedicColors.canvas, insetPadding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerRight, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))),
            Flexible(child: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _placeholder(error: true)))),
            const SizedBox(height: 16),
          ]))),
          child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _placeholder(error: true)));
      })));
}
