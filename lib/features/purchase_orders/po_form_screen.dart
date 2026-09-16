import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'po_models.dart';
import 'po_repository.dart';
import 'po_status_ui.dart';

/// Create or edit a purchase order. Pass an existing [poId] to edit/view;
/// omit it to create a new draft. Pops `true` on save/delete so the list
/// refreshes.
///
/// The purchase order IS the form — same as the web `PurchaseOrderDocument`:
/// there's no separate "fill details, then preview the bill" step. Header
/// fields, item lines with a fixed GST-slab dropdown (0/5/18%) and running
/// totals are all editable directly; Save writes it.
///
/// The web version prints via the browser's native print-to-PDF
/// (`window.print()` on a styled HTML layout) — there is no client-side PDF
/// library involved on that side either. This screen intentionally mirrors
/// that: an editable/viewable document with no PDF export, since adding one
/// here would require a new dependency the web original doesn't use.
class PoFormScreen extends ConsumerStatefulWidget {
  const PoFormScreen({super.key, this.poId});
  final int? poId;

  @override
  ConsumerState<PoFormScreen> createState() => _PoFormScreenState();
}

class _PoFormScreenState extends ConsumerState<PoFormScreen> {
  late final TextEditingController _supplierName;
  late final TextEditingController _supplierAddress;
  late final TextEditingController _supplierGstin;
  late final TextEditingController _shippingName;
  late final TextEditingController _shippingAddress;
  late final TextEditingController _remarks;

  DateTime _poDate = DateTime.now();
  String? _poNumber;
  String? _createdByUsername;
  List<_ItemRow> _items = [_ItemRow.empty()];

  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.poId != null;

  @override
  void initState() {
    super.initState();
    _supplierName = TextEditingController();
    _supplierAddress = TextEditingController();
    _supplierGstin = TextEditingController();
    _shippingName = TextEditingController();
    _shippingAddress = TextEditingController();
    _remarks = TextEditingController();
    if (widget.poId != null) _load(widget.poId!);
  }

  Future<void> _load(int id) async {
    setState(() => _loading = true);
    try {
      final po = await ref.read(poRepositoryProvider).get(id);
      if (!mounted) return;
      setState(() {
        _poDate = po.poDate ?? DateTime.now();
        _supplierName.text = po.supplierName ?? '';
        _supplierAddress.text = po.supplierAddress ?? '';
        _supplierGstin.text = po.supplierGstin ?? '';
        _shippingName.text = po.shippingName ?? '';
        _shippingAddress.text = po.shippingAddress ?? '';
        _remarks.text = po.remarks ?? '';
        _poNumber = po.poNumber;
        _createdByUsername = po.createdByUsername;
        _items = po.items.isNotEmpty
            ? po.items.map((i) => _ItemRow.fromItem(i)).toList()
            : [_ItemRow.empty()];
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _supplierName.dispose();
    _supplierAddress.dispose();
    _supplierGstin.dispose();
    _shippingName.dispose();
    _shippingAddress.dispose();
    _remarks.dispose();
    for (final it in _items) {
      it.description.dispose();
      it.quantity.dispose();
      it.unitPrice.dispose();
    }
    super.dispose();
  }

  void _addItem() => setState(() => _items.add(_ItemRow.empty()));

  void _removeItem(int idx) {
    if (_items.length <= 1) return;
    setState(() {
      final removed = _items.removeAt(idx);
      removed.description.dispose();
      removed.quantity.dispose();
      removed.unitPrice.dispose();
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _poDate,
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
    );
    if (d != null) setState(() => _poDate = d);
  }

  ({double subtotal, double gstTotal, double grandTotal}) _totals() {
    double subtotal = 0, gstTotal = 0, grandTotal = 0;
    for (final it in _items) {
      final qty = double.tryParse(it.quantity.text) ?? 0;
      final price = double.tryParse(it.unitPrice.text) ?? 0;
      final base = qty * price;
      final gst = base * (it.gstPercent / 100);
      subtotal += base;
      gstTotal += gst;
      grandTotal += base + gst;
    }
    return (subtotal: subtotal, gstTotal: gstTotal, grandTotal: grandTotal);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final items = <PoItem>[];
    for (final it in _items) {
      final desc = it.description.text.trim();
      if (desc.isEmpty) continue;
      items.add(PoItem(
        description: desc,
        quantity: double.tryParse(it.quantity.text) ?? 0,
        unitPrice: double.tryParse(it.unitPrice.text) ?? 0,
        gstPercent: it.gstPercent,
      ));
    }
    if (items.isEmpty) {
      setState(() => _error = 'Add at least one item with a description.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(poRepositoryProvider);
    try {
      final saved = _isEdit
          ? await repo.update(
              widget.poId!,
              poDate: _poDate,
              supplierName: _emptyToNull(_supplierName.text),
              supplierAddress: _emptyToNull(_supplierAddress.text),
              supplierGstin: _emptyToNull(_supplierGstin.text),
              shippingName: _emptyToNull(_shippingName.text),
              shippingAddress: _emptyToNull(_shippingAddress.text),
              remarks: _emptyToNull(_remarks.text),
              items: items,
            )
          : await repo.create(
              poDate: _poDate,
              supplierName: _emptyToNull(_supplierName.text),
              supplierAddress: _emptyToNull(_supplierAddress.text),
              supplierGstin: _emptyToNull(_supplierGstin.text),
              shippingName: _emptyToNull(_shippingName.text),
              shippingAddress: _emptyToNull(_shippingAddress.text),
              remarks: _emptyToNull(_remarks.text),
              items: items,
            );
      if (!mounted) return;
      setState(() {
        _poNumber = saved.poNumber;
        _createdByUsername = saved.createdByUsername;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEdit ? 'Purchase order saved' : 'Purchase order ${saved.poNumber} created')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.poId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete purchase order?'),
        content: Text('Delete purchase order ${_poNumber ?? ''}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(poRepositoryProvider).delete(widget.poId!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String? _emptyToNull(String s) => s.trim().isEmpty ? null : s.trim();

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    final totals = _totals();
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_poNumber ?? (_isEdit ? 'Purchase Order' : 'New Purchase Order')),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
          actions: [
            if (_isEdit)
              IconButton(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                tooltip: 'Delete',
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_createdByUsername != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('Created by $_createdByUsername',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ),
                  const AppSectionHeader(title: 'Order details'),
                  const SizedBox(height: 10),
                  _label('Date *'),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 15, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(df.format(_poDate),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const AppSectionHeader(title: 'Supplier'),
                  const SizedBox(height: 8),
                  _label('Name'),
                  TextField(controller: _supplierName, textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 10),
                  _label('Address'),
                  TextField(controller: _supplierAddress, minLines: 2, maxLines: 4),
                  const SizedBox(height: 10),
                  _label('GSTIN'),
                  TextField(
                    controller: _supplierGstin,
                    maxLength: 15,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                    decoration: const InputDecoration(counterText: ''),
                  ),
                  const SizedBox(height: 16),
                  const AppSectionHeader(title: 'Shipping address'),
                  const SizedBox(height: 8),
                  _label('Name'),
                  TextField(controller: _shippingName, textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 10),
                  _label('Address'),
                  TextField(controller: _shippingAddress, minLines: 2, maxLines: 4),
                  const SizedBox(height: 18),
                  AppSectionHeader(
                    title: 'Items',
                    trailing: TextButton.icon(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add item'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _items.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ItemCard(
                        row: _items[i],
                        removable: _items.length > 1,
                        onChanged: () => setState(() {}),
                        onRemove: () => _removeItem(i),
                      ),
                    ),
                  const SizedBox(height: 8),
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    shadow: AppShadows.soft,
                    child: Column(
                      children: [
                        _totalRow('Subtotal (before GST)', totals.subtotal),
                        const SizedBox(height: 6),
                        _totalRow('Total GST', totals.gstTotal),
                        const Divider(height: 18),
                        _totalRow('Grand total', totals.grandTotal, bold: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label('Remarks / payment instructions'),
                  TextField(controller: _remarks, minLines: 2, maxLines: 4),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    AppErrorPanel(message: _error!),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create order')),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
      );

  Widget _totalRow(String label, double value, {bool bold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: bold ? 13.5 : 12.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  color: bold ? AppColors.ink : AppColors.inkSoft)),
          Text(poMoney(value),
              style: TextStyle(
                  fontSize: bold ? 15 : 12.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                  color: AppColors.ink)),
        ],
      );
}

/// Mutable, form-friendly staging of one item line — text controllers for
/// free-typed quantity/unit price, a fixed `gstPercent` slab (see
/// [PoConstants.gstOptions]).
class _ItemRow {
  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unitPrice;
  double gstPercent;

  _ItemRow({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.gstPercent,
  });

  factory _ItemRow.empty() => _ItemRow(
        description: TextEditingController(),
        quantity: TextEditingController(text: '1'),
        unitPrice: TextEditingController(),
        gstPercent: 18,
      );

  factory _ItemRow.fromItem(PoItem item) => _ItemRow(
        description: TextEditingController(text: item.description),
        quantity: TextEditingController(
            text: item.quantity == item.quantity.roundToDouble()
                ? item.quantity.toStringAsFixed(0)
                : item.quantity.toString()),
        unitPrice: TextEditingController(text: item.unitPrice.toStringAsFixed(2)),
        gstPercent: item.gstPercent,
      );
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.row,
    required this.removable,
    required this.onChanged,
    required this.onRemove,
  });

  final _ItemRow row;
  final bool removable;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  double get _base =>
      (double.tryParse(row.quantity.text) ?? 0) * (double.tryParse(row.unitPrice.text) ?? 0);
  double get _gst => _base * (row.gstPercent / 100);

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.description,
                  decoration: const InputDecoration(hintText: 'Item description'),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => onChanged(),
                ),
              ),
              if (removable)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.danger),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.quantity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Qty'),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: row.unitPrice,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Unit price', prefixText: '₹ '),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: DropdownButtonFormField<double>(
                  value: row.gstPercent,
                  decoration: const InputDecoration(labelText: 'GST'),
                  items: [
                    for (final g in PoConstants.gstOptions)
                      DropdownMenuItem(value: g.toDouble(), child: Text('$g%')),
                  ],
                  onChanged: (v) {
                    row.gstPercent = v ?? row.gstPercent;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('GST ${poMoney(_gst)}  ·  ',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              Text('Total ${poMoney(_base + _gst)}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Uppercases GSTIN input as it's typed (mirrors the web's
/// `.toUpperCase()` on the GSTIN field).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
