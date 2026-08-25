import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController(text: 'admin@kaj.com');
  final passController = TextEditingController(text: '123456');
  bool loading = false;

  Future<void> login() async {
    setState(() => loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: emailController.text,
        password: passController.text,
      );
      if (mounted) context.go('/');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('KAJ ERP', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(controller: emailController, decoration: const InputDecoration(labelText: 'الايميل', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: passController, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة السر', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity,
              child: ElevatedButton(onPressed: loading ? null : login, 
                child: loading ? const CircularProgressIndicator() : const Text('دخول')),
            ),
          ]),
        ),
      ),
    );
  }
}