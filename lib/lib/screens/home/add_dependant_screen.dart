import 'package:medictrack/design/medic_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/dependant_service.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy    = MedicColors.c142F2B;
  static const teal    = MedicColors.c28715D;
  static const sky     = MedicColors.c477C91;
  static const amber   = MedicColors.cB77A27;
  static const rose    = MedicColors.cC05256;
  static const violet  = MedicColors.c78659B;
  static const surface = MedicColors.cF6F5F0;
  static const card    = MedicColors.cFFFFFF;
  static const border  = MedicColors.cE2E5DC;
  static const textPri = MedicColors.c142F2B;
  static const textSec = MedicColors.c63756D;
  static const textTer = MedicColors.c83938B;
}

/// Add a dependant by their MedicTrack Patient ID. Sends a request that the
/// other person must explicitly accept before any of their data is visible.
class AddDependantScreen extends StatefulWidget {
  const AddDependantScreen({Key? key}) : super(key: key);

  @override
  State<AddDependantScreen> createState() => _AddDependantScreenState();
}

class _AddDependantScreenState extends State<AddDependantScreen> {
  final _codeCtrl = TextEditingController();
  final _dependantSvc = DependantService();

  bool _searching = false;
  bool _sending = false;
  Map<String, dynamic>? _found;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _searching = true; _found = null; _error = null; });
    final result = await _dependantSvc.findUserByCode(code);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _found = result;
      _error = result == null ? 'No user found with ID "${code.toUpperCase()}"' : null;
    });
  }

  Future<void> _sendRequest() async {
    setState(() => _sending = true);
    final result = await _dependantSvc.sendRequest(_codeCtrl.text.trim());
    if (!mounted) return;
    setState(() => _sending = false);
    _snack(result['message'], error: !(result['success'] as bool));
    if (result['success'] == true) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: Colors.white, size: 15),
        const SizedBox(width: 9),
        Expanded(child: Text(msg, style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      backgroundColor: _C.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(14),
    ));
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: _C.surface,
      body: Column(children: [
        _buildHeader(),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _C.teal.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _C.teal.withOpacity(0.2))),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: _C.teal, size: 18),
                const SizedBox(width: 10),
                const Expanded(child: Text(
                  'Ask the person for their Patient ID (find it on their Profile screen). '
                      'They\'ll get a request and must accept it before you can see their health data.',
                  style: TextStyle(fontSize: 12, color: _C.textSec, height: 1.4),
                )),
              ]),
            ),
            const SizedBox(height: 24),

            const Text('Patient ID', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Container(
                decoration: BoxDecoration(
                    color: _C.card, borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _C.border, width: 1.5)),
                child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: _C.textPri, letterSpacing: 4),
                  decoration: const InputDecoration(
                    hintText: '7K3PQ2',
                    hintStyle: TextStyle(
                        color: _C.textTer, letterSpacing: 4, fontWeight: FontWeight.w700),
                    prefixIcon: Icon(Icons.badge_outlined, color: _C.teal),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              )),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _searching ? null : _search,
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                      color: _C.teal, borderRadius: BorderRadius.circular(16)),
                  child: Center(child: _searching
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Icon(Icons.search_rounded, color: Colors.white)),
                ),
              ),
            ]),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: _C.rose.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _C.rose.withOpacity(0.25))),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: _C.rose, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: const TextStyle(
                      fontSize: 12.5, color: _C.rose, fontWeight: FontWeight.w600))),
                ]),
              ),
            ],

            if (_found != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: _C.card, borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _C.teal.withOpacity(0.3), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
                        blurRadius: 14, offset: const Offset(0, 5))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                          color: _C.teal.withOpacity(0.12), shape: BoxShape.circle),
                      child: Center(child: Text(
                          ((_found!['fullName'] as String?) ?? 'U').trim().isNotEmpty
                              ? (_found!['fullName'] as String)[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                              color: _C.teal))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_found!['fullName'] ?? 'User', style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, color: _C.textPri)),
                      const SizedBox(height: 3),
                      Text('ID: ${_found!['patientCode'] ?? '—'}'
                          '${_found!['age'] != null ? ' · Age ${_found!['age']}' : ''}',
                          style: const TextStyle(fontSize: 12, color: _C.textSec)),
                    ])),
                  ]),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _sending ? null : _sendRequest,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 50, width: double.infinity,
                      decoration: BoxDecoration(
                          color: _sending ? _C.teal.withOpacity(0.6) : _C.teal,
                          borderRadius: BorderRadius.circular(14)),
                      child: Center(child: _sending
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Send Tracking Request', style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                            ])),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
        )),
      ]),
    ),
  );

  Widget _buildHeader() => const MedicPageTitle(
    title: 'Care for someone', subtitle: 'Connect with a family member, with their consent.',
  );
}

class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.2), 90,
        Paint()..color = _C.amber.withOpacity(0.08));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.85), 70,
        Paint()..color = _C.sky.withOpacity(0.06));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
