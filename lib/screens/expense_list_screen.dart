import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/expense_model.dart';
import '../widgets/currency_converter_card.dart';
import 'add_expense_screen.dart';

// A simple, fixed mapping from category name to a color - used by
// both the pie chart slices and the legend below it, so they stay
// visually consistent with each other. Private to this file since
// only this screen's chart/legend needs it.
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

// Turns a stored "YYYY-MM-DD" date string into a more readable label:
// "Today"/"Yesterday" for the two most recent days, a weekday name
// ("Monday", "Tuesday"...) for anything within the last week, and the
// actual date once it's older than that - similar to how WhatsApp,
// Slack, etc. label message timestamps.
String _relativeDateLabel(String storedDate) {
  final date = DateTime.tryParse(storedDate);
  // Old expenses saved before the date picker existed may still have
  // the literal string "Today" stored - tryParse returns null for
  // those, so we just show the raw (bad) value rather than crashing.
  if (date == null) return storedDate;

  final now = DateTime.now();
  // Truncate both to midnight before comparing, so "2:00 PM today" vs
  // "11:00 PM yesterday" doesn't accidentally count as > 24 hours apart.
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(date.year, date.month, date.day);
  final daysAgo = today.difference(thatDay).inDays;

  if (daysAgo == 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';

  if (daysAgo > 1 && daysAgo < 7) {
    const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    // DateTime.weekday is 1-7 (Monday=1), so subtract 1 for a 0-based index.
    return weekdayNames[date.weekday - 1];
  }

  // Older than a week (or the rare same-day-but-negative edge case) -
  // fall back to a readable actual date, e.g. "12 Sep 2026".
  const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${date.day} ${monthNames[date.month - 1]} ${date.year}';
}

class ExpenseListScreen extends StatelessWidget {
  const ExpenseListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ExpenseModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('My Expenses')),
      // CustomScrollView + slivers instead of Column + Expanded(ListView) -
      // a Column only lets ONE child scroll (whichever one you wrap in
      // Expanded+ListView), everything else stays pinned. A
      // CustomScrollView makes the WHOLE page one continuous scroll area,
      // so the total/converter/chart scroll away naturally along with
      // the expense list, instead of staying fixed at the top.
      body: CustomScrollView(
        slivers: [
          // SliverToBoxAdapter: "drop this ordinary widget into the
          // scroll" - used for anything that isn't itself a list.
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.green.shade100,
              width: double.infinity,
              child: Column(
                children: [
                  const Text('Total Spent'),
                  Text(
                    'RM ${model.total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: CurrencyConverterCard(totalInMyr: model.total),
          ),

          // --- CHART SECTION (only shown when there's data to chart) ---
          if (model.expenses.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
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
                                  // Expanded + ellipsis: if the label is too
                                  // long for the available space, it truncates
                                  // with "..." instead of overflowing the Row.
                                  Expanded(
                                    child: Text(
                                      '${entry.key}: RM ${entry.value.toStringAsFixed(2)}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
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
            ),

          // The expense list itself. Empty state uses SliverToBoxAdapter
          // (just one static widget); non-empty state uses SliverList so
          // each row is lazily built as you scroll, same laziness ListView
          // .builder used to give you, just inside the shared scroll now.
          if (model.expenses.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No expenses yet - tap + to add one')),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
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
                          content: Text('Delete "${expense.category}" (RM ${expense.amount.toStringAsFixed(2)})?'),
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
                            ? _relativeDateLabel(expense.date)
                            : '${_relativeDateLabel(expense.date)} - ${expense.note}',
                      ),
                      trailing: Text('RM ${expense.amount.toStringAsFixed(2)}'),
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
                childCount: model.expenses.length,
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
