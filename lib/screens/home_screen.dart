import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('KAJ ERP - الرئيسية')),
      body: Center(child: Text('مرحبا ${user?.email} \n تم تسجيل الدخول بنجاح')),
    );
  }
}