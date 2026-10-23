import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}
class _RegisterScreenState extends State<RegisterScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false, _obscure = true;

  Future<void> _register() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final base = ApiConfig.baseUrl.replaceFirst(RegExp(r'/$'), '');
      final response = await http.post(Uri.parse('$base/api/auth/register'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: json.encode({'full_name': _name.text.trim(), 'email': _email.text.trim(), 'password': _password.text}));
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 201) {
        if (!mounted) return;
        final message = data['message']?.toString() ?? 'Registro procesado';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        if (data['authenticated'] == true) {
          Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
        } else {
          Navigator.of(context).pop();
        }
      } else {
        throw Exception(data['detail'] ?? 'No fue posible crear la cuenta');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  void dispose() { _name.dispose(); _email.dispose(); _password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crear cuenta')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Form(key: _key, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(Icons.rocket_launch_outlined, size: 64),
      const SizedBox(height: 16),
      const Text('Únete a Bitácora Lightyear', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 24),
      TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nombre completo', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)), validator: (v) => v == null || v.trim().length < 2 ? 'Ingresa tu nombre' : null),
      const SizedBox(height: 14),
      TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo electrónico', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email_outlined)), validator: (v) => v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? 'Ingresa un correo válido' : null),
      const SizedBox(height: 14),
      TextFormField(controller: _password, obscureText: _obscure, decoration: InputDecoration(labelText: 'Contraseña (mínimo 8 caracteres)', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscure = !_obscure)),), validator: (v) => v == null || v.length < 8 ? 'La contraseña debe tener al menos 8 caracteres' : null),
      const SizedBox(height: 20),
      FilledButton(onPressed: _loading ? null : _register, child: Padding(padding: const EdgeInsets.all(12), child: _loading ? const CircularProgressIndicator() : const Text('Crear cuenta'))),
    ]))))),
  );
}
