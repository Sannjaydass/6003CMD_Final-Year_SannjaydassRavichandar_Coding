import 'package:flutter/material.dart';

/// Dispose editor controllers when the dialog actually leaves the tree,
/// after its closing animation, rather than when Navigator.pop resolves.
class MedicDialogControllerScope extends StatefulWidget {
  final List<TextEditingController> controllers;
  final Widget child;
  const MedicDialogControllerScope({super.key, required this.controllers, required this.child});
  @override
  State<MedicDialogControllerScope> createState() => _MedicDialogControllerScopeState();
}
class _MedicDialogControllerScopeState extends State<MedicDialogControllerScope> {
  @override
  void dispose() {
    for (final controller in widget.controllers) { controller.dispose(); }
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => widget.child;
}
