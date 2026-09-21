import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../services/database_helper.dart';

// ============================================================
// THE SHARED STATE - backed by a real database instead of just
// an in-memory list. Data survives app restarts. This is the
// "hub" of the app - every screen and widget reads from or
// writes to this one shared instance via Provider, instead of
// talking to each other directly.
// ============================================================
class ExpenseModel extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  List<Expense> _expenses = [];

  // Shared currency state, visible to every screen via
  // context.watch<ExpenseModel>(). MYR is our storage/base currency -
  // amounts are always ENTERED and STORED in MYR. displayCurrency is
  // purely what the user wants the total CONVERTED to for viewing,
  // it never changes what's actually saved to the database.
  String displayCurrency = 'MYR';

  void setDisplayCurrency(String currency) {
    displayCurrency = currency;
    notifyListeners();
  }

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
