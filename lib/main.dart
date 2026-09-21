import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/expense_model.dart';
import 'screens/expense_list_screen.dart';

void main() {
  runApp(const MyApp());
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
        title: 'Expense Tracker - Database Version',
        theme: ThemeData(primarySwatch: Colors.green),
        home: const ExpenseListScreen(),
      ),
    );
  }
}
