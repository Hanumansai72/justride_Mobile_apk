import '../../../core/services/ride_history_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/fuel_stop_service.dart';
import '../../../core/services/ride_planning_store.dart';

Future<double?> showFuelRangeDialog(BuildContext context) async {
  final owner = await RidePlanningStore.owner();
  final prefs = await SharedPreferences.getInstance();
  final recent =
      await RideHistoryService.instance.localHistory(owner, recentLimit: 5);
  final rides = recent
      .where((ride) => ride.distanceKm >= 2 && ride.durationSeconds >= 180)
      .toList();
  final suggestHeavy = rides.length >= 2 &&
      rides.where((ride) => ride.averageSpeedKmh < 25).length * 2 >
          rides.length;
  if (!context.mounted ||
      owner != await RidePlanningStore.owner() ||
      !context.mounted) return null;
  return showDialog<double>(
    context: context,
    builder: (context) => _FuelRangeDialog(
        owner: owner, prefs: prefs, suggestHeavy: suggestHeavy),
  );
}

class _FuelRangeDialog extends StatefulWidget {
  const _FuelRangeDialog(
      {required this.owner, required this.prefs, required this.suggestHeavy});
  final String owner;
  final SharedPreferences prefs;
  final bool suggestHeavy;

  @override
  State<_FuelRangeDialog> createState() => _FuelRangeDialogState();
}

class _FuelRangeDialogState extends State<_FuelRangeDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _economy, _reserve;
  final _fuel = TextEditingController();
  late FuelRidingStyle _style;
  String get _prefix => 'fuel_profile_${widget.owner}';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _economy = TextEditingController(
        text: widget.prefs.getString('${_prefix}_economy'));
    _reserve = TextEditingController(
        text: widget.prefs.getString('${_prefix}_reserve') ?? '1');
    final name = widget.prefs.getString('${_prefix}_style');
    _style = FuelRidingStyle.values.firstWhere((style) => style.name == name,
        orElse: () => widget.suggestHeavy
            ? FuelRidingStyle.heavy
            : FuelRidingStyle.mixed);
  }

  @override
  void dispose() {
    _economy.dispose();
    _reserve.dispose();
    _fuel.dispose();
    super.dispose();
  }

  Widget _number(String label, TextEditingController controller, double minimum,
          double maximum) =>
      TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          final amount = double.tryParse(value?.trim() ?? '');
          return amount == null ||
                  !amount.isFinite ||
                  amount < minimum ||
                  amount > maximum
              ? 'Enter a value from $minimum to $maximum'
              : null;
        },
      );

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    final litres = double.parse(_fuel.text.trim());
    final reserve = double.parse(_reserve.text.trim());
    if (litres <= reserve) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Your fuel estimate is already at or below your reserve. Refuel before departure.')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.owner != await RidePlanningStore.owner()) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final range = plannedFuelRangeKm(
          baseKmPerLitre: double.parse(_economy.text.trim()),
          litres: litres,
          reserveLitres: reserve,
          style: _style);
      await Future.wait([
        widget.prefs.setString('${_prefix}_economy', _economy.text.trim()),
        widget.prefs.setString('${_prefix}_reserve', _reserve.text.trim()),
        widget.prefs.setString('${_prefix}_style', _style.name),
      ]);
      if (mounted) Navigator.pop(context, range);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Plan a fuel stop'),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _number('Typical fuel economy (km/L)', _economy, 1, 100),
                _number('Fuel remaining now (L)', _fuel, .1, 50),
                _number('Keep in reserve (L)', _reserve, 0, 25),
                DropdownButtonFormField<FuelRidingStyle>(
                  initialValue: _style,
                  decoration:
                      const InputDecoration(labelText: 'Expected riding style'),
                  items: [
                    for (final style in FuelRidingStyle.values)
                      DropdownMenuItem(value: style, child: Text(style.label))
                  ],
                  onChanged: (style) =>
                      setState(() => _style = style ?? _style),
                ),
                const SizedBox(height: 12),
                if (widget.suggestHeavy)
                  const Text(
                      'Recent rides averaged under 25 km/h often. Consider the stop-and-go buffer.'),
                const Text(
                    'Range is an estimate. Mixed uses a 10% buffer; stop-and-go or brisk uses 25%. Check your bike’s fuel gauge before leaving.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _saving ? null : _submit,
              child: const Text('Find fuel')),
        ],
      );
}
