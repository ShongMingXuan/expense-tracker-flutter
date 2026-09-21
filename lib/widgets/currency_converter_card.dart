import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_model.dart';
import '../services/exchange_rate_service.dart';

// ============================================================
// CURRENCY CONVERTER CARD - StatefulWidget because it needs to
// hold onto the Future itself (_ratesFuture) between rebuilds,
// so FutureBuilder can watch the SAME Future across multiple
// rebuilds rather than accidentally starting a new API call
// every single time the widget rebuilds.
// ============================================================
class CurrencyConverterCard extends StatefulWidget {
  final double totalInMyr;

  const CurrencyConverterCard({super.key, required this.totalInMyr});

  @override
  State<CurrencyConverterCard> createState() => _CurrencyConverterCardState();
}

class _CurrencyConverterCardState extends State<CurrencyConverterCard> {
  final ExchangeRateService _service = ExchangeRateService();

  // null = haven't fetched yet (button not pressed). Once set, this
  // is the SAME Future object across rebuilds - critical detail below.
  Future<Map<String, double>>? _ratesFuture;

  // MYR itself doesn't need "conversion" - it's already the stored
  // amount - so it's left out of this list and handled as a special
  // case in build() below.
  final List<String> _currencyOptions = ['USD', 'EUR', 'GBP', 'JPY', 'SGD', 'AUD'];

  void _fetchRates() {
    setState(() {
      // Rebase to MYR instead of the API's raw USD-based rates.
      _ratesFuture = _service.fetchRatesRelativeTo('MYR');
    });
  }

  @override
  Widget build(BuildContext context) {
    // Currency selection lives on ExpenseModel, not local state -
    // this is what lets any other screen read/react to it later too.
    final selectedCurrency = context.watch<ExpenseModel>().displayCurrency;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Convert total to ', style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      value: selectedCurrency,
                      items: [
                        const DropdownMenuItem(value: 'MYR', child: Text('MYR')),
                        ..._currencyOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                      ],
                      onChanged: (value) {
                        // Write through the shared model instead of setState -
                        // read() because we're firing an action, not listening.
                        context.read<ExpenseModel>().setDisplayCurrency(value!);
                      },
                    ),
                  ],
                ),
                TextButton(onPressed: _fetchRates, child: const Text('Fetch Rate')),
              ],
            ),

            // MYR selected: nothing to convert or fetch, just show the
            // stored total directly.
            if (selectedCurrency == 'MYR')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'RM ${widget.totalInMyr.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),

            // A different currency is selected, but we haven't fetched
            // rates yet this session.
            if (selectedCurrency != 'MYR' && _ratesFuture == null)
              const Text('Tap "Fetch Rate" to see the live conversion'),

            // FutureBuilder only appears once _ratesFuture is non-null -
            // this is what actually watches the Future's state over time.
            if (selectedCurrency != 'MYR' && _ratesFuture != null)
              FutureBuilder<Map<String, double>>(
                future: _ratesFuture,
                builder: (context, snapshot) {
                  // STATE 1: still waiting on the network call.
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Fetching live rate...'),
                        ],
                      ),
                    );
                  }

                  // STATE 2: the Future completed, but with an error
                  // (thrown by our service - e.g. bad status code, or
                  // a genuine network failure like no internet).
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Failed to fetch rate: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }

                  // STATE 3: success - snapshot.data is now the actual
                  // Map<String, double> our service returned, already
                  // rebased so keys mean "1 MYR = ? X".
                  final rates = snapshot.data!;
                  final selectedRate = rates[selectedCurrency];
                  if (selectedRate == null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('$selectedCurrency rate not found in response'),
                    );
                  }
                  final converted = widget.totalInMyr * selectedRate;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'RM ${widget.totalInMyr.toStringAsFixed(2)} \u2248 $selectedCurrency ${converted.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
