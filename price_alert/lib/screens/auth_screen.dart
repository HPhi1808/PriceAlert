import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pin_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _isOtpSent = false;
  bool _isLoading = false;

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      if (!_isOtpSent) {
        await Supabase.instance.client.auth.signInWithOtp(email: _emailCtrl.text.trim());
        setState(() => _isOtpSent = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi mã OTP vào email!')));
      } else {
        final response = await Supabase.instance.client.auth.verifyOTP(
          email: _emailCtrl.text.trim(),
          token: _otpCtrl.text.trim(),
          type: OtpType.email,
        );
        if (response.session != null) {
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const PinScreen(isCreating: true))
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Đăng Nhập")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder()),
              enabled: !_isOtpSent,
            ),
            const SizedBox(height: 10),
            if (_isOtpSent)
              TextField(
                controller: _otpCtrl,
                decoration: const InputDecoration(labelText: "Nhập mã OTP (6 số)", border: OutlineInputBorder()),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _signIn,
                child: Text(_isOtpSent ? "Xác Nhận OTP" : "Gửi Mã Xác Thực"),
              ),
            ),
            if (_isOtpSent)
              TextButton(
                  onPressed: () => setState(() => _isOtpSent = false),
                  child: const Text("Gửi lại hoặc đổi Email"))
          ],
        ),
      ),
    );
  }
}