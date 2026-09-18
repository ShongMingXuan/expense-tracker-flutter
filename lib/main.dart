import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'models/expense.dart';
import 'services/database_helper.dart';
import 'services/exchange_rate_service.dart';

void main() {
  runApp(const MyApp());
}

// ============================================================
// THE SHARED STATE - now backed by a real database instead of
// just an in-memory list. Data survives app restarts now.
// ============================================================
class ExpenseModel extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  List<Expense> _expenses = [];

  List<Expense> get expenses => List.unmodifiable(_expenses);
  double get total => _expenses.fold(0, (sum, e) => sum + e.amount);

  // Groups expenses by category and sums each group's amount -
  // this is exactly what a GROUP BY + SUM would do in SQL, just
  // done in Dart over the in-memory list instead of a query.
  Map<String, double> get categoryTotals {
    final Map<String, double> totals = {};
    for (var expense in _expenses) {
      totals[expense.category] = (totals[expense.category] ?? 0) + expense.amount;
    }
    return totals;
  }

  // Call this once when the app starts, to populate _expenses from
  // whatever was already saved on disk from previous sessions.
  Future<void> loadExpenses() async {
    _expenses = await _db.getAllExpenses();
    notifyListeners();
  }

  Future<void> addExpense(Expense expense) async {
    // Save to the database FIRST, so we get back the real assigned id...
    final id = await _db.insertExpense(expense);
    // ...then create a copy of the expense WITH that id, and add it
    // to our in-memory list too - this keeps the in-memory list and
    // the database in sync without needing to re-query everything.
    final savedExpense = Expense(
      id: id,
      category: expense.category,
      amount: expense.amount,
      date: expense.date,
      note: expense.note,
    );
    _expenses.add(savedExpense);
    notifyListeners();
  }

  Future<void> updateExpense(Expense expense) async {
    await _db.updateExpense(expense);
    // Find the matching entry in the in-memory list by id, and
    // replace it with the updated version.
    final index = _expenses.indexWhere((e) => e.id == expense.id);
    if (index != -1) {
      _expenses[index] = expense;
      notifyListeners();
    }
  }

  Future<void> deleteExpense(int id) async {
    // Delete from the database first...
    await _db.deleteExpense(id);
    // ...then remove it from the in-memory list too, same
    // "keep both in sync" pattern as addExpense above.
    _expenses.removeWhere((expense) => expense.id == id);
    notifyListeners();
  }
}

// A simple, fixed mapping from category name to a color - used by
// both the pie chart slices and the legend below it, so they stay
// visually consistent with each other.
Color _colorForCategory(String category) {
  switch (category) {
    case 'Food':
      return Colors.orange;
    case 'Transport':
      return Colors.blue;
    case 'Groceries':
      return Colors.green;
    case 'Entertainment':
      return Colors.purple;
    default:
      return Colors.grey;
  }
}

// ============================================================
// CURRENCY CONVERTER CARD - StatefulWidget because it needs to
// hold onto the Future itself (_ratesFuture) between rebuilds,
// so FutureBuilder can watch the SAME Future across multiple
// rebuilds rather than accidentally starting a new API call
// every single time the widget rebuilds.
// ============================================================
class CurrencyConverterCard extends StatefulWidget {
  final double totalInUsd;

  const CurrencyConverterCard({super.key, required this.totalInUsd});

  @override
  State<CurrencyConverterCard> createState() => _CurrencyConverterCardState();
}

class _CurrencyConverterCardState extends State<CurrencyConverterCard> {
  final ExchangeRateService _service = ExchangeRateService();

  // null = haven't fetched yet (button not pressed). Once set, this
  // is the SAME Future object across rebuilds - critical detail below.
  Future<Map<String, double>>? _ratesFuture;

  // The currently selected target currency - defaults to MYR.
  String _selectedCurrency = 'MYR';
  final List<String> _currencyOptions = ['MYR', 'EUR', 'GBP', 'JPY', 'SGD', 'AUD'];

  void _fetchRates() {
    setState(() {
      _ratesFuture = _service.fetchRates();
    });
  }

  @override
  Widget build(BuildContext context) {
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
                      value: _selectedCurrency,
                      items: _currencyOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCurrency = value!;
                          // Changing currency doesn't need a NEW api call -
                          // we already have every currency's rate from the
                          // last fetch, we're just reading a different key.
                        });
                      },
                    ),
                  ],
                ),
                TextButton(onPressed: _fetchRates, child: const Text('Fetch Rate')),
              ],
            ),
            // If no fetch has happened yet, just show a placeholder message.
            if (_ratesFuture == null)
              const Text('Tap "Fetch Rate" to see the live conversion'),

            // FutureBuilder only appears once _ratesFuture is non-null -
            // this is what actually watches the Future's state over time.
            if (_ratesFuture != null)
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
                  // Map<String, double> our service returned.
                  final rates = snapshot.data!;
                  final selectedRate = rates[_selectedCurrency];
                  if (selectedRate == null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('$_selectedCurrency rate not found in response'),
                    );
                  }
                  final converted = widget.totalInUsd * selectedRate;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '\$${widget.totalInUsd.toStringAsFixed(2)} \u2248 $_selectedCurrency ${converted.toStringAsFixed(2)}',
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ExpenseModel()..loadExpenses(),
      // The ..loadExpenses() above uses Dart's "cascade" operator -
      // it means "create the ExpenseModel, THEN immediately call
      // loadExpenses() on that same object, then use the object
      // (not loadExpenses()'s return value) as the actual result."
      child: MaterialApp(
        title: 'Expense Tracker',
        theme: ThemeData(primarySwatch: Colors.green),
        home: const ExpenseListScreen(),
      ),
    );
  }
}

class ExpenseListScreen extends StatelessWidget {
  const ExpenseListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ExpenseModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('My Expenses')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.green.shade100,
            width: double.infinity,
            child: Column(
              children: [
                const Text('Total Spent'),
                Text(
                  '\$${model.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          CurrencyConverterCard(totalInUsd: model.total),

          // --- CHART SECTION (only shown when there's data to chart) ---
          if (model.expenses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 160,
                child: Row(
                  children: [
                    // The actual pie chart - takes up the left half.
                    Expanded(
                      child: PieChart(
                        PieChartData(
                          sections: model.categoryTotals.entries.map((entry) {
                            return PieChartSectionData(
                              value: entry.value,
                              color: _colorForCategory(entry.key),
                              // showTitle: false keeps the slices clean -
                              // the legend on the right explains what's what.
                              showTitle: false,
                            );
                          }).toList(),
                          sectionsSpace: 2,
                          centerSpaceRadius: 30,
                        ),
                      ),
                    ),
                    // A simple text legend on the right, since PieChart
                    // itself doesn't draw one for you automatically.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: model.categoryTotals.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  color: _colorForCategory(entry.key),
                                ),
                                const SizedBox(width: 8),
                                Text('${entry.key}: \$${entry.value.toStringAsFixed(2)}'),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Expanded(
            child: model.expenses.isEmpty
                ? const Center(child: Text('No expenses yet - tap + to add one'))
                : ListView.builder(
                    itemCount: model.expenses.length,
                    itemBuilder: (context, index) {
                      final expense = model.expenses[index];
                      return Dismissible(
                        // Key must be unique per item - the database id is
                        // perfect for this, since it never changes or repeats.
                        // Without a proper key, Flutter can get confused about
                        // which widget is which after one gets removed.
                        key: ValueKey(expense.id),
                        direction: DismissDirection.endToStart, // swipe right-to-left only
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        // confirmDismiss lets you show a confirmation dialog
                        // BEFORE the item actually disappears - returning
                        // false/null cancels the dismiss, keeping the item.
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete expense?'),
                              content: Text('Delete "${expense.category}" (\$${expense.amount.toStringAsFixed(2)})?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                        },
                        // onDismissed only fires AFTER confirmDismiss returns
                        // true - this is where the actual deletion happens.
                        onDismissed: (direction) {
                          context.read<ExpenseModel>().deleteExpense(expense.id!);
                        },
                        child: ListTile(
                          title: Text(expense.category),
                          subtitle: Text(
                            (expense.note == null || expense.note!.isEmpty)
                                ? expense.date
                                : '${expense.date} - ${expense.note}',
                          ),
                          trailing: Text('\$${expense.amount.toStringAsFixed(2)}'),
                          // Tapping opens the SAME AddExpenseScreen, but this
                          // time WITH an expense passed in - that's the signal
                          // that puts it into "editing" mode instead of "adding".
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AddExpenseScreen(expenseToEdit: expense),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddExpenseScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class AddExpenseScreen extends StatefulWidget {
  // If this is null, we're adding a NEW expense.
  // If it's provided, we're EDITING that specific expense.
  final Expense? expenseToEdit;

  const AddExpenseScreen({super.key, this.expenseToEdit});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late String _selectedCategory;
  final List<String> _categories = ['Food', 'Transport', 'Groceries', 'Entertainment', 'Other'];

  // A quick helper to check which mode we're in, used in a few places.
  bool get _isEditing => widget.expenseToEdit != null;

  @override
  void initState() {
    super.initState();
    // initState runs ONCE, when this screen is first created - the
    // right place to pre-fill fields from widget.expenseToEdit if
    // we're editing, since build() runs many times but this doesn't.
    final existing = widget.expenseToEdit;
    _amountController = TextEditingController(text: existing?.amount.toString() ?? '');
    _noteController = TextEditingController(text: existing?.note ?? '');
    _selectedCategory = existing?.category ?? 'Food';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitExpense() async {
    final double? amount = double.tryParse(_amountController.text);
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }

    final model = context.read<ExpenseModel>();

    if (_isEditing) {
      // Editing: keep the same id and date, only the user-editable
      // fields change. Passing the original id is what tells
      // updateExpense() WHICH row to overwrite.
      final updatedExpense = Expense(
        id: widget.expenseToEdit!.id,
        category: _selectedCategory,
        amount: amount,
        date: widget.expenseToEdit!.date,
        note: _noteController.text,
      );
      await model.updateExpense(updatedExpense);
    } else {
      final newExpense = Expense(
        category: _selectedCategory,
        amount: amount,
        date: 'Today',
        note: _noteController.text,
      );
      await model.addExpense(newExpense);
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Title and button text change based on mode, so it's clear
      // to the user which action they're actually performing.
      appBar: AppBar(title: Text(_isEditing ? 'Edit Expense' : 'Add Expense')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '\$ ', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _selectedCategory = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitExpense,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_isEditing ? 'Save Changes' : 'Add Expense'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}