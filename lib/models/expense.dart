// The single source of truth for what an "Expense" looks like across
// your whole app - screens, the shared state model, and the database
// all use this same class now, instead of the old FakeExpense.
class Expense {
  final int? id; // null until saved to the database, which assigns it
  final String category;
  final double amount;
  final String date;
  final String? note;

  Expense({this.id, required this.category, required this.amount, required this.date, this.note});

  // Converts an Expense object INTO a Map, which is what sqflite's
  // insert()/update() methods expect.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'amount': amount,
      'date': date,
      'note': note,
    };
  }

  // The reverse - converts a Map (a row fetched FROM the database)
  // back into a proper Expense object.
  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      category: map['category'] as String,
      amount: map['amount'] as double,
      date: map['date'] as String,
      note: map['note'] as String?,
    );
  }
}