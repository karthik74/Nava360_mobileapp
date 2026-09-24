import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'rent_models.dart';
import 'rent_repository.dart';

/// Full-access-only card for managing the GST / TDS rate dropdowns offered on the branch form
/// (web `RentRateOptionsCard`). [onChanged] receives the fresh list after every server call.
class RentRateOptionsCard extends StatefulWidget {
  const RentRateOptionsCard({super.key, required this.repo, required this.options, required this.onChanged});
  final RentRepository repo;
  final RentRateOptions options;
  final ValueChanged<RentRateOptions> onChanged;

  @override
  State<RentRateOptionsCard> createState() => _RentRateOptionsCardState();
}

class _RentRateOptionsCardState extends State<RentRateOptionsCard> {
  bool _busy = false;

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _run(Future<RentRateOptions> Function() fn) async {
    setState(() => _busy = true);
    try {
      widget.onChanged(await fn());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<double?> _ask(String title, {double? initial}) {
    final c = TextEditingController(text: initial == null ? '' : _fmt(initial));
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Rate %', suffixText: '%'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = double.tryParse(c.text.trim());
              if (n == null || n < 0 || n > 100) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Enter a rate between 0 and 100.')));
                return;
              }
              Navigator.pop(ctx, n);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _list(String label, String type, List<double> values) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final v in values)
              InputChip(
                label: Text(type == 'TDS' && v == 0 ? 'Not applicable' : '${_fmt(v)}%'),
                onPressed: _busy
                    ? null
                    : () async {
                        final n = await _ask('Edit $type rate', initial: v);
                        if (n != null) await _run(() => widget.repo.editRateOption(type, v, n));
                      },
                onDeleted: _busy ? null : () => _run(() => widget.repo.deleteRateOption(type, v)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add'),
              onPressed: _busy
                  ? null
                  : () async {
                      final n = await _ask('Add $type rate');
                      if (n != null) await _run(() => widget.repo.addRateOption(type, n));
                    },
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GST / TDS rate options', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          const Text('Full access only. Rates offered when adding or editing a branch.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
          const SizedBox(height: 10),
          _list('GST rates', 'GST', widget.options.gstRates),
          const SizedBox(height: 10),
          _list('TDS rates', 'TDS', widget.options.tdsRates),
        ],
      ),
    );
  }
}
