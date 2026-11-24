import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CommunityBudgetScreen extends StatefulWidget {
  const CommunityBudgetScreen({super.key});
  @override
  State<CommunityBudgetScreen> createState() => _CommunityBudgetScreenState();
}

class _CommunityBudgetScreenState extends State<CommunityBudgetScreen> {
  static const _key = 'justride_community_budget_v1';
  final _distance = TextEditingController();
  final _mileage = TextEditingController(text: '35');
  final _fuelPrice = TextEditingController(text: '105');
  final _nights = TextEditingController(text: '0');
  final _room = TextEditingController(text: '1500');
  final _foodDay = TextEditingController(text: '500');
  final _tolls = TextEditingController(text: '0');
  final _other = TextEditingController(text: '0');
  double _buffer = 10;
  bool _ready = false;

  List<TextEditingController> get _controllers => [
        _distance,
        _mileage,
        _fuelPrice,
        _nights,
        _room,
        _foodDay,
        _tolls,
        _other
      ];

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final values = jsonDecode(raw) as Map<String, dynamic>;
        for (final item in values.entries) {
          final controller = switch (item.key) {
            'distance' => _distance,
            'mileage' => _mileage,
            'fuelPrice' => _fuelPrice,
            'nights' => _nights,
            'room' => _room,
            'foodDay' => _foodDay,
            'tolls' => _tolls,
            'other' => _other,
            _ => null,
          };
          if (controller != null && item.value is String)
            controller.text = item.value as String;
        }
        _buffer = (values['buffer'] as num?)?.toDouble() ?? _buffer;
      } catch (_) {
        /* Ignore an invalid saved estimate and let the rider re-enter it. */
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  double _number(TextEditingController value) =>
      (double.tryParse(value.text.trim()) ?? 0).clamp(0, 10000000).toDouble();
  double get _fuel => _number(_mileage) > 0
      ? _number(_distance) / _number(_mileage) * _number(_fuelPrice)
      : 0;
  double get _lodging => _number(_nights) * _number(_room);
  double get _food => (_number(_nights) + 1) * _number(_foodDay);
  double get _subtotal =>
      _fuel + _lodging + _food + _number(_tolls) + _number(_other);
  double get _total => _subtotal * (1 + _buffer / 100);

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key,
        jsonEncode({
          'distance': _distance.text,
          'mileage': _mileage.text,
          'fuelPrice': _fuelPrice.text,
          'nights': _nights.text,
          'room': _room.text,
          'foodDay': _foodDay.text,
          'tolls': _tolls.text,
          'other': _other.text,
          'buffer': _buffer,
        }));
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Budget estimate saved on this device.')));
  }

  Widget _field(TextEditingController controller, String label,
          {bool decimal = true}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
              controller: controller,
              keyboardType: TextInputType.numberWithOptions(decimal: decimal),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: label)));

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Trip budget planner'), actions: [
          IconButton(
              tooltip: 'Save estimate',
              onPressed: _ready ? _save : null,
              icon: const Icon(Icons.save_outlined))
        ]),
        body: !_ready
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(20), children: [
                const Text(
                    'Enter your own planning assumptions. Fuel prices and community-reported costs are estimates, not live quotes.'),
                const SizedBox(height: 12),
                _field(_distance, 'Round-trip distance (km)'),
                _field(_mileage, 'Motorcycle mileage (km/L)'),
                _field(_fuelPrice, 'Fuel price (₹/L)'),
                _field(_nights, 'Accommodation nights', decimal: false),
                _field(_room, 'Room cost per night (₹)'),
                _field(_foodDay, 'Food per day (₹)'),
                _field(_tolls, 'Tolls total (₹)'),
                _field(_other, 'Other costs (₹)'),
                Row(children: [
                  const Expanded(child: Text('Contingency')),
                  Text('${_buffer.round()}%')
                ]),
                Slider(
                    value: _buffer,
                    min: 0,
                    max: 30,
                    divisions: 6,
                    label: '${_buffer.round()}%',
                    onChanged: (value) => setState(() => _buffer = value)),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Estimated total  ₹${_total.round()}',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const Divider(),
                              _line('Fuel', _fuel),
                              _line('Accommodation', _lodging),
                              _line('Food', _food),
                              _line('Tolls', _number(_tolls)),
                              _line('Other', _number(_other)),
                              _line('Contingency (${_buffer.round()}%)',
                                  _subtotal * _buffer / 100),
                            ]))),
                const SizedBox(height: 8),
                FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save estimate on device')),
              ]),
      );

  Widget _line(String label, double value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
          children: [Expanded(child: Text(label)), Text('₹${value.round()}')]));
}
