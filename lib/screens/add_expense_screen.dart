import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_model.dart';

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
  late DateTime _selectedDate;
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

    // Old expenses saved before this feature existed have the literal
    // string "Today" stored as their date, which DateTime.tryParse()
    // can't understand - it returns null for anything it can't parse.
    // In that case (or when adding a brand new expense) we fall back
    // to DateTime.now(), so the field always has SOMETHING valid to show.
    _selectedDate = existing != null
        ? (DateTime.tryParse(existing.date) ?? DateTime.now())
        : DateTime.now();
  }

  // Formats a DateTime as "YYYY-MM-DD" - a plain, sortable, unambiguous
  // format to store in the database. padLeft(2, '0') ensures single-digit
  // months/days get a leading zero (e.g. "2026-09-05", not "2026-9-5").
  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  // showDatePicker returns a Future<DateTime?> - same "wait for the user
  // to finish interacting" pattern as showDialog in the delete confirmation
  // on the list screen. Returns null if the user backs out without picking.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    // picked is null if the user tapped Cancel/backed out - in that
    // case, leave _selectedDate exactly as it was.
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
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
      // Editing: keep the same id, but the date is now editable too -
      // formatted from whatever the user picked (or left unchanged).
      final updatedExpense = Expense(
        id: widget.expenseToEdit!.id,
        category: _selectedCategory,
        amount: amount,
        date: _formatDate(_selectedDate),
        note: _noteController.text,
      );
      await model.updateExpense(updatedExpense);
    } else {
      final newExpense = Expense(
        category: _selectedCategory,
        amount: amount,
        date: _formatDate(_selectedDate),
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
              decoration: const InputDecoration(labelText: 'Amount', prefixText: 'RM ', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _selectedCategory = v!),
            ),
            const SizedBox(height: 16),
            // InkWell makes the whole field tappable (not just some inner
            // button), and wraps an InputDecorator so it LOOKS like a
            // normal form field even though it's actually read-only text
            // plus a tap handler - the real editing happens in the
            // showDatePicker dialog that _pickDate() opens.
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder()),
                child: Text(_formatDate(_selectedDate)),
              ),
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
