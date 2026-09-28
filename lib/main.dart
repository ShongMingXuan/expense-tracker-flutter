import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/expense_model.dart';
import 'screens/expense_list_screen.dart';
import 'screens/login_screen.dart';
import 'providers/user_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ExpenseModel()..loadExpenses()),
        ChangeNotifierProvider(create: (context) => UserProvider()),
      ],
      child: MaterialApp(
        title: 'Expense Tracker - Database Version',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(primarySwatch: Colors.green),
        home: const LoginScreen(),
        routes: {
          '/home': (context) => const ExpenseListScreen(),
        },
      ),
    );
      // (not loadExpenses()'s return value) as the actual result."
  }
}
