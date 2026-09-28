import 'package:flutter/material.dart';

class UserProvider extends ChangeNotifier {
  String username = '';

  // Hardcoded for now, since there's no sign-up/database yet -
  final String _correctPassword = 'password123';

  void updateUsername(String newUsername) {
    username = newUsername;
    notifyListeners();
  }

  bool checkPassword(String enteredPassword) {
    return enteredPassword == _correctPassword;
  }

  void logout() {
    username = '';
    notifyListeners();
  }
}