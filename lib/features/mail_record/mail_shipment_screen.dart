import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/pro_ui.dart';
import '../../core/widgets.dart';
import 'mail_list_screen.dart' show mailBranchesProvider, mailMyBranchIdProvider, mailStockForBranchProvider;
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
  static const _othersValue = '__OTHERS__';
  String? _item;
  final _otherItem = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  int? _fromBranchId;
  int? _toBranchId;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The shipment leaves from the signed-in user's own branch by default (still changeable).
    ref.read(mailMyBranchIdProvider.future).then((id) {
      if (mounted && id != null) setState(() => _fromBranchId ??= id);
    });
  }

  @override
  void dispose() {
    _quantity.dispose();
    _otherItem.dispose();
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
    final itemName = _item == _othersValue ? _otherItem.text.trim() : _item;
    if (itemName == null || itemName.isEmpty || qty == null || qty <= 0) {
      setState(() => _error = 'Pick an item and enter a positive quantity.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(mailRepositoryProvider).dispatchShipment(
            fromBranchId: _fromBranchId!,
            toBranchId: _toBranchId!,
            itemName: itemName,
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'Dispatch shipment',
        subtitle: 'Mail record · stationery to another branch',
      ),
      bottomNavigationBar: branchesAsync.hasValue
          ? ProBottomBar(
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _dispatch,
                  icon: const Icon(Icons.local_shipping_rounded, size: 18),
                  label: Text(_saving ? 'Dispatching…' : 'Dispatch'),
                ),
              ],
            )
          : null,
      body: branchesAsync.when(
        data: (branches) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ProSectionHeader(title: 'Route'),
                  const SizedBox(height: 12),
                  ProField(
                    label: 'From',
                    required: true,
                    child: DropdownButtonFormField<int>(
                      value: _fromBranchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.north_east_rounded, size: 18),
                      ),
                      items: [
                        for (final b in branches)
                          DropdownMenuItem(value: b.id, child: Text(b.label, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _fromBranchId = v),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ProField(
                    label: 'To',
                    required: true,
                    child: DropdownButtonFormField<int>(
                      value: _toBranchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.south_west_rounded, size: 18),
                      ),
                      items: [
                        for (final b in branches)
                          DropdownMenuItem(value: b.id, child: Text(b.label, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _toBranchId = v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ProSectionHeader(title: 'Item'),
                  const SizedBox(height: 12),
                  ProField(
                    label: 'Item',
                    required: true,
                    child: _fromBranchId == null
                        ? const ProNote('Pick the From branch first.')
                        : ref.watch(mailStockForBranchProvider(_fromBranchId!)).when(
                              // The item list is shared by every branch — an admin maintains it.
                              data: (items) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: _item == _othersValue || items.any((i) => i.itemName == _item) ? _item : null,
                                    hint: const Text('Select an item'),
                                    items: [
                                      for (final i in items)
                                        DropdownMenuItem(
                                            value: i.itemName, child: Text(i.itemName, overflow: TextOverflow.ellipsis)),
                                      const DropdownMenuItem(value: _othersValue, child: Text('Others')),
                                    ],
                                    onChanged: (v) => setState(() => _item = v),
                                  ),
                                  if (_item == _othersValue) ...[
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: _otherItem,
                                      maxLength: 120,
                                      decoration: const InputDecoration(hintText: 'Enter item name'),
                                    ),
                                  ],
                                ],
                              ),
                              loading: () => const LinearProgressIndicator(),
                              error: (e, _) =>
                                  Text('$e', style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                            ),
                  ),
                  const SizedBox(height: 14),
                  ProField(
                    label: 'Quantity',
                    required: true,
                    child: TextField(
                      controller: _quantity,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: AppText.number.copyWith(fontSize: 15, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              ProNote(_error!, tone: ProNoteTone.bad),
            ],
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AppErrorPanel(message: '$e'),
          ),
        ),
      ),
    );
  }
}
