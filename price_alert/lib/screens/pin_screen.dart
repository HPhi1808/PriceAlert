import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'auth_screen.dart';

class PinScreen extends StatefulWidget {
  final bool isCreating;

  const PinScreen({super.key, required this.isCreating});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final _storage = const FlutterSecureStorage();
  String _pin = "";
  String _confirmPin = "";
  bool _isConfirming = false;

  void _onKeyPress(String val) {
    if (_pin.length < 6) {
      setState(() => _pin += val);
      if (_pin.length == 6) _submitPin();
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  Future<void> _submitPin() async {
    if (widget.isCreating) {
      if (_isConfirming) {
        if (_pin == _confirmPin) {
          await _storage.write(key: 'user_pin', value: _pin);
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
            );
          }
        } else {
          _showError("Mã PIN không khớp! Vui lòng nhập lại.");
          setState(() {
            _pin = "";
            _confirmPin = "";
            _isConfirming = false;
          });
        }
      } else {
        setState(() {
          _confirmPin = _pin;
          _pin = "";
          _isConfirming = true;
        });
      }
    } else {
      String? storedPin = await _storage.read(key: 'user_pin');
      if (_pin == storedPin) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else {
        _showError("Sai mã PIN!");
        setState(() => _pin = "");
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: index < _pin.length ? Colors.blue : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }

  Widget _buildKeypad() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildRow(['1', '2', '3']),
          const SizedBox(height: 20),
          _buildRow(['4', '5', '6']),
          const SizedBox(height: 20),
          _buildRow(['7', '8', '9']),
          const SizedBox(height: 20),
          _buildRow([null, '0', 'del']),
        ],
      ),
    );
  }

  Widget _buildRow(List<dynamic> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((k) {
        if (k == null) {
          return const SizedBox(width: 70, height: 70);
        }
        if (k == 'del') {
          // Nút xóa
          return SizedBox(
            width: 70, height: 70,
            child: InkWell(
              onTap: _onDelete,
              borderRadius: BorderRadius.circular(50),
              child: const Icon(Icons.backspace_outlined, size: 28),
            ),
          );
        }
        // Phím số
        return _buildKey(k);
      }).toList(),
    );
  }

  Widget _buildKey(String val) {
    return SizedBox(
      width: 70, height: 70,
      child: InkWell(
        onTap: () => _onKeyPress(val),
        borderRadius: BorderRadius.circular(50),
        child: Center(
          child: Text(
            val,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.isCreating
        ? (_isConfirming ? "Xác nhận lại mã PIN" : "Tạo mã PIN mới")
        : "Nhập mã PIN";

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 30),
                      const Icon(Icons.lock_outline, size: 60, color: Colors.blue),
                      const SizedBox(height: 20),
                      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      if (!widget.isCreating)
                        TextButton(
                          onPressed: () async {
                            await _storage.deleteAll();
                            await Supabase.instance.client.auth.signOut();
                            if (mounted) {
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (_) => const AuthScreen()),
                                    (route) => false,
                              );
                            }
                          },
                          child: const Text("Quên mã PIN? Đăng nhập lại bằng Email"),
                        ),

                      const SizedBox(height: 30),
                      _buildPinDots(),

                      const Spacer(),

                      Container(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: _buildKeypad(),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}