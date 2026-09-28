import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {

  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login Page'),
      ),
      body:Column (
        children: [
          Text('Welcome to the Login Page', style: TextStyle(fontSize: 24)
      ),
      TextField(
        controller:usernameController,
        decoration: InputDecoration(
          labelText: 'Username',
        ),
      ),
      TextField(
        controller: passwordController,
        decoration: InputDecoration(
          labelText: 'Password',
        ),
        obscureText: true,
      ),
      ElevatedButton(
          onPressed: () {
            // Get the username and password from the text controllers
            String username = usernameController.text;
            String password = passwordController.text;
            // Here you can add your authentication logic
            if (username.isEmpty || password.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please fill in both fields')),
              );
              return;   // stops here, doesn't navigate
            }
            final userProvider = context.read<UserProvider>();

            if (userProvider.checkPassword(password)) {
              userProvider.updateUsername(username);
              Navigator.pushReplacementNamed(context, '/home');
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Wrong password')),
              );
            }
          },
          child: const Text('Login')
        ),
      ], 
      )
    );
  }

    @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}