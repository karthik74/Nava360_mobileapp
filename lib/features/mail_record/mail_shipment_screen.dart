import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mail_list_screen.dart' show mailBranchesProvider;
import 'mail_repository.dart';

/// Dispatch a new inter-branch stationery shipment. Pops `true` on
/// dispatch so the Stock & Shipments tab refreshes. Mirrors
/// `AdminMailPage.tsx`'s `StockTab` "Dispatch shipment" modal — receiving a
/// shipment (full or partial, which moves its status from `DISPATCHED` to
/// `PARTIALLY_RECEIVED`/`RECEIVED`) is handled inline in the shipments list
/// via a quantity field + "Receive" button, same as the web's inline table
/// row controls.
class MailShipmentScreen extends ConsumerStatefulWidget {
  const MailShipmentScreen({super.key});

  @override
  ConsumerState<MailShipmentScreen> createState() => _MailShipmentScreenState();
}

class _MailShipmentScreenState extends ConsumerState<MailShipmentScreen> {
  final _itemName = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  int? _fromBranchId;
  int? _toBranchId;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _itemName.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _dispatch() async {
    setState(() => _error = null);
    if (_fromBranchId == null || _toBranchId == null) {
      setState(() => _error = 'Select both branches.');
      return;
    }
    if (_fromBranchId == _toBranchId) {
      setState(() => _error = 'From and to branches must differ.');
      return;
    }
    final qty = num.tryParse(_quantity.text);
    if (_itemName.text.trim().isEmpty || qty == null || qty <= 0) {
      setState(() => _error = 'Enter an item name and a positive quantity.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(mailRepositoryProvider).dispatchShipment(
            fromBranchId: _fromBranchId!,
            toBranchId: _toBranchId!,
            itemName: _itemName.text.trim(),
            quantity: qty,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shipment dispatched')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(mailBranchesProvider);
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Dispatch Shipment'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: branchesAsync.when(
          data: (branches) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _label('From *'),
              DropdownButtonFormField<int>(
                value: _fromBranchId,
                items: [for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.label))],
                onChanged: (v) => setState(() => _fromBranchId = v),
              ),
              const SizedBox(height: 10),
              _label('To *'),
              DropdownButtonFormField<int>(
                value: _toBranchId,
                items: [for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.label))],
                onChanged: (v) => setState(() => _toBranchId = v),
              ),
              const SizedBox(height: 10),
              _label('Item name *'),
              TextField(controller: _itemName),
              const SizedBox(height: 10),
              _label('Quantity *'),
              TextField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                AppErrorPanel(message: _error!),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _saving ? null : _dispatch,
                  child: Text(_saving ? 'Dispatching…' : 'Dispatch'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: AppErrorPanel(message: '$e')),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(t,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
      );
}
