import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'po_models.dart';
import 'po_pdf.dart';
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
  // Company block — editable; what is saved becomes this user's own default.
  late final TextEditingController _coAddress;
  late final TextEditingController _coGstin;
  late final TextEditingController _coCin;
  late final TextEditingController _coMobile;
  late final TextEditingController _coEmail;
  /// Typed by the user; left blank, a PO-YYYY-NNNN number is assigned when it is saved.
  late final TextEditingController _poNumberInput;

  DateTime _poDate = DateTime.now();
  /// Only today … today + 30 days can be picked, counted from the day the PO is being made.
  DateTime? _deliveryByDate;
  static const _deliveryWindowDays = 30;
  String? _poNumber;
  String? _createdByUsername;
  List<_ItemRow> _items = [_ItemRow.empty()];

  bool _loading = false;
  bool _saving = false;
  bool _companyOpen = false;
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
    _coAddress = TextEditingController();
    _coGstin = TextEditingController();
    _coCin = TextEditingController();
    _coMobile = TextEditingController();
    _coEmail = TextEditingController();
    _poNumberInput = TextEditingController();
    if (widget.poId != null) {
      _load(widget.poId!);
    } else {
      _loadMyDetails();
    }
  }

  void _fillCompany(Map<String, String> c) {
    _coAddress.text = c['address'] ?? '';
    _coGstin.text = c['gstin'] ?? '';
    _coCin.text = c['cin'] ?? '';
    _coMobile.text = c['mobile'] ?? '';
    _coEmail.text = c['email'] ?? '';
  }

  /// A new PO starts with this user's own saved company details.
  Future<void> _loadMyDetails() async {
    try {
      final c = await ref.read(poRepositoryProvider).myDetails();
      if (mounted) setState(() => _fillCompany(c));
    } catch (_) {
      // The fields just stay blank and can be typed in.
    }
  }

  Map<String, String> get _companyPayload => {
        'address': _coAddress.text.trim(),
        'gstin': _coGstin.text.trim(),
        'cin': _coCin.text.trim(),
        'mobile': _coMobile.text.trim(),
        'email': _coEmail.text.trim(),
      };

  Future<void> _load(int id) async {
    setState(() => _loading = true);
    try {
      final po = await ref.read(poRepositoryProvider).get(id);
      if (!mounted) return;
      setState(() {
        _poDate = po.poDate ?? DateTime.now();
        _deliveryByDate = po.deliveryByDate;
        _fillCompany(po.company);
        _poNumberInput.text = po.poNumber;
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
    _coAddress.dispose();
    _coGstin.dispose();
    _coCin.dispose();
    _coMobile.dispose();
    _coEmail.dispose();
    _remarks.dispose();
    _poNumberInput.dispose();
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

  Future<void> _pickDeliveryDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final last = today.add(const Duration(days: _deliveryWindowDays));
    var initial = _deliveryByDate ?? today;
    if (initial.isBefore(today) || initial.isAfter(last)) initial = today;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: last,
      helpText: 'Please do delivery before this date (next $_deliveryWindowDays days)',
    );
    if (d != null) setState(() => _deliveryByDate = d);
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
    if (_deliveryByDate == null) {
      setState(() => _error = 'Pick the date the products should be delivered by.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(poRepositoryProvider);
    try {
      final saved = _isEdit
          ? await repo.update(
              widget.poId!,
              poNumber: _emptyToNull(_poNumberInput.text),
              poDate: _poDate,
              deliveryByDate: _deliveryByDate,
              company: _companyPayload,
              supplierName: _emptyToNull(_supplierName.text),
              supplierAddress: _emptyToNull(_supplierAddress.text),
              supplierGstin: _emptyToNull(_supplierGstin.text),
              shippingName: _emptyToNull(_shippingName.text),
              shippingAddress: _emptyToNull(_shippingAddress.text),
              remarks: _emptyToNull(_remarks.text),
              items: items,
            )
          : await repo.create(
              poNumber: _emptyToNull(_poNumberInput.text),
              poDate: _poDate,
              deliveryByDate: _deliveryByDate,
              company: _companyPayload,
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: _poNumber ?? (_isEdit ? 'Purchase order' : 'New purchase order'),
        subtitle: _createdByUsername != null
            ? 'Created by $_createdByUsername'
            : 'Purchase orders',
        actions: [
          if (_isEdit)
            IconButton(
              onPressed: () => downloadPoPdf(context, () => ref.read(poRepositoryProvider).get(widget.poId!)),
              icon: Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary),
              tooltip: 'Download PDF',
            ),
          if (_isEdit)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              tooltip: 'Delete',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ProSectionHeader(title: 'Order details'),
                      const SizedBox(height: 12),
                      ProField(
                        label: 'PO number',
                        child: TextField(
                          controller: _poNumberInput,
                          maxLength: 30,
                          decoration: const InputDecoration(hintText: 'Leave blank for an automatic number', counterText: ''),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ProField(
                        label: 'Date',
                        required: true,
                        child: _PickerBox(
                          icon: Icons.calendar_today_rounded,
                          text: df.format(_poDate),
                          onTap: _pickDate,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _companyCard(),
                const SizedBox(height: 14),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ProSectionHeader(title: 'Supplier'),
                      const SizedBox(height: 12),
                      ProField(
                        label: 'Name',
                        child: TextField(controller: _supplierName, textCapitalization: TextCapitalization.words),
                      ),
                      const SizedBox(height: 14),
                      ProField(
                        label: 'Address',
                        child: TextField(controller: _supplierAddress, minLines: 2, maxLines: 4),
                      ),
                      const SizedBox(height: 14),
                      ProField(
                        label: 'GSTIN',
                        child: TextField(
                          controller: _supplierGstin,
                          maxLength: 15,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [UpperCaseTextFormatter()],
                          decoration: const InputDecoration(counterText: ''),
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
                      const ProSectionHeader(title: 'Shipping address'),
                      const SizedBox(height: 12),
                      ProField(
                        label: 'Name',
                        child: TextField(controller: _shippingName, textCapitalization: TextCapitalization.words),
                      ),
                      const SizedBox(height: 14),
                      ProField(
                        label: 'Address',
                        child: TextField(controller: _shippingAddress, minLines: 2, maxLines: 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                ProSectionHeader(
                  title: 'Items',
                  subtitle: '${_items.length} item(s)',
                  trailing: TextButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add item'),
                  ),
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < _items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ItemCard(
                      index: i + 1,
                      row: _items[i],
                      removable: _items.length > 1,
                      onChanged: () => setState(() {}),
                      onRemove: () => _removeItem(i),
                    ),
                  ),
                const SizedBox(height: 4),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ProSectionHeader(title: 'Summary'),
                      const SizedBox(height: 4),
                      ProKeyValue(rows: [
                        MapEntry('Subtotal (before GST)', poMoney(totals.subtotal)),
                        MapEntry('Total GST', poMoney(totals.gstTotal)),
                      ]),
                      const Divider(height: 18, color: AppColors.hairline),
                      _totalRow('Grand total', totals.grandTotal, bold: true),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ProSectionHeader(title: 'Delivery & remarks'),
                      const SizedBox(height: 12),
                      ProField(
                        label: 'Remarks / payment instructions',
                        child: TextField(controller: _remarks, minLines: 2, maxLines: 4),
                      ),
                      const SizedBox(height: 14),
                      ProField(
                        label: 'Please do delivery before this date',
                        required: true,
                        child: _PickerBox(
                          icon: Icons.event_available_rounded,
                          text: _deliveryByDate == null
                              ? 'Pick a date (next $_deliveryWindowDays days)'
                              : df.format(_deliveryByDate!),
                          placeholder: _deliveryByDate == null,
                          onTap: _pickDeliveryDate,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  AppErrorPanel(message: _error!),
                ],
              ],
            ),
      bottomNavigationBar: _loading
          ? null
          : ProBottomBar(
              top: _totalRow('Grand total', totals.grandTotal, bold: true),
              children: [
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create order')),
                ),
              ],
            ),
    );
  }

  /// Company block — collapsible card with a one-line summary when closed.
  Widget _companyCard() {
    final summary = [
      _coAddress.text.trim().split('\n').first,
      if (_coGstin.text.trim().isNotEmpty) 'GSTIN ${_coGstin.text.trim()}',
    ].where((s) => s.isNotEmpty).join(' · ');
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _companyOpen = !_companyOpen),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    ProIconWell(icon: Icons.business_rounded, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Company details', style: AppText.section),
                          Text(
                            summary.isEmpty ? 'Tap to add the company block' : summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _companyOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more_rounded, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_companyOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1, color: AppColors.hairlineSoft),
                  const SizedBox(height: 14),
                  ProField(
                    label: 'Address',
                    child: TextField(controller: _coAddress, minLines: 2, maxLines: 3, maxLength: 500, decoration: const InputDecoration(counterText: '')),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ProField(
                          label: 'GSTIN',
                          child: TextField(
                            controller: _coGstin,
                            maxLength: 30,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(counterText: ''),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ProField(
                          label: 'Mobile',
                          child: TextField(controller: _coMobile, keyboardType: TextInputType.phone, maxLength: 30, decoration: const InputDecoration(counterText: '')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ProField(
                    label: 'CIN',
                    child: TextField(
                      controller: _coCin,
                      maxLength: 40,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(counterText: ''),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ProField(
                    label: 'Email',
                    child: TextField(controller: _coEmail, keyboardType: TextInputType.emailAddress, maxLength: 150, decoration: const InputDecoration(counterText: '')),
                  ),
                  const SizedBox(height: 8),
                  const Text('Saved with this order and kept as your own default for the next one.',
                      style: AppText.caption),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool bold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: bold ? 15 : 14,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                  color: bold ? AppColors.ink : AppColors.muted)),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(poMoney(value),
                  style: TextStyle(
                      fontSize: bold ? 18 : 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: bold ? -0.3 : 0,
                      color: AppColors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
        ],
      );
}

/// Input-styled tappable box for the date pickers.
class _PickerBox extends StatelessWidget {
  const _PickerBox({
    required this.icon,
    required this.text,
    required this.onTap,
    this.placeholder = false,
  });
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InputDecorator(
        decoration: InputDecoration(prefixIcon: Icon(icon, size: 18)),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: placeholder ? AppColors.faint : AppColors.ink,
          ),
        ),
      ),
    );
  }
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
    required this.index,
    required this.row,
    required this.removable,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.neutralTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$index',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
              ),
              const SizedBox(width: 10),
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
                  tooltip: 'Remove item',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ProField(
                  label: 'Qty',
                  child: TextField(
                    controller: row.quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ProField(
                  label: 'Unit price',
                  child: TextField(
                    controller: row.unitPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(prefixText: '₹ '),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('GST', style: AppText.label),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final g in PoConstants.gstOptions)
                      ChoiceChip(
                        label: Text('$g%'),
                        selected: row.gstPercent == g.toDouble(),
                        onSelected: (_) {
                          row.gstPercent = g.toDouble();
                          onChanged();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.hairlineSoft),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text('GST ${poMoney(_gst)}',
                    style: AppText.caption.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              Text('Total ${poMoney(_base + _gst)}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      fontFeatures: [FontFeature.tabularFigures()])),
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
