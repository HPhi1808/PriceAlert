import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

class CreateAlertScreen extends StatefulWidget {
  const CreateAlertScreen({super.key});
  @override
  State<CreateAlertScreen> createState() => _CreateAlertScreenState();
}

class _CreateAlertScreenState extends State<CreateAlertScreen> {
  final List<String> _symbols = ['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT'];
  String _selectedSymbol = 'BTCUSDT';
  double _currentPrice = 0.0;

  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final _teleCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));

  bool _isLoading = false;
  bool _isFetchingPrice = false;

  Timer? _priceTimer;

  @override
  void initState() {
    super.initState();
    _fetchCurrentPrice(isBackground: false);
    _priceTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchCurrentPrice(isBackground: true);
    });
  }

  @override
  void dispose() {
    _priceTimer?.cancel();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _teleCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentPrice({bool isBackground = false}) async {
    if (!isBackground) {
      setState(() => _isFetchingPrice = true);
    }

    double price = 0.0;

    // ƯU TIÊN 1: COINBASE
    try {
      price = await _getPriceFromCoinbase(_selectedSymbol);
    } catch (e) {
      // debugPrint("Coinbase lỗi: $e");
    }

    // ƯU TIÊN 2: BINANCE
    if (price == 0) {
      try {
        price = await _getPriceFromBinance(_selectedSymbol);
      } catch (e) {
        // debugPrint("Binance lỗi: $e");
      }
    }

    if (mounted) {
      setState(() {
        if (price > 0) {
          _currentPrice = price;
        }
        _isFetchingPrice = false;
      });
      if (price == 0 && !isBackground) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Không lấy được giá. Đang thử lại...'))
        );
      }
    }
  }

  Future<double> _getPriceFromCoinbase(String rawSymbol) async {
    final symbol = rawSymbol.replaceAll("USDT", "").toUpperCase();
    final url = Uri.parse("https://api.coinbase.com/v2/prices/$symbol-USD/spot");
    final response = await http.get(url, headers: {"User-Agent": "Mozilla/5.0"});

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return double.parse(data['data']['amount']);
    }
    throw Exception("Coinbase status: ${response.statusCode}");
  }

  Future<double> _getPriceFromBinance(String rawSymbol) async {
    final rand = DateTime.now().millisecondsSinceEpoch;
    final url = Uri.parse("https://api.binance.us/api/v3/ticker/price?symbol=$rawSymbol&rand=$rand");
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return double.parse(data['price']);
    }
    throw Exception("Binance status: ${response.statusCode}");
  }

  Future<void> _handleSave() async {
    final now = DateTime.now();
    if (_selectedDate.difference(now).inHours < 24) {
      _showErrorDialog('⏳ Thời gian hiệu lực phải ít nhất là 1 ngày!');
      return;
    }

    final minPrice = double.tryParse(_minCtrl.text) ?? 0;
    final maxPrice = double.tryParse(_maxCtrl.text) ?? 0;

    if (minPrice <= 0 && maxPrice <= 0) {
      _showErrorDialog('⚠️ Bạn phải nhập ít nhất Giá Min hoặc Giá Max (lớn hơn 0).');
      return;
    }

    if (_currentPrice > 0) {
      if (minPrice > 0 && minPrice >= _currentPrice) {
        _showErrorDialog('⛔ Giá Sàn (Min) phải NHỎ HƠN giá hiện tại ($_currentPrice).');
        return;
      }
      if (maxPrice > 0 && maxPrice <= _currentPrice) {
        _showErrorDialog('⛔ Giá Trần (Max) phải LỚN HƠN giá hiện tại ($_currentPrice).');
        return;
      }
    }

    bool needsWarning = false;
    String warningMsg = "";

    if (minPrice > 0 && minPrice < _currentPrice * 0.5) {
      needsWarning = true;
      warningMsg += "- Giá Min ($minPrice) thấp hơn 50% giá hiện tại.\n";
    }
    if (maxPrice > 0 && maxPrice > _currentPrice * 1.5) {
      needsWarning = true;
      warningMsg += "- Giá Max ($maxPrice) cao hơn 150% giá hiện tại.\n";
    }

    if (needsWarning) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("⚠️ Cảnh báo nhập liệu"),
          content: Text("$warningMsg\nBạn có chắc chắn muốn đặt mức giá này không?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Kiểm tra lại")),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _saveToSupabase();
              },
              child: const Text("Vẫn Lưu"),
            ),
          ],
        ),
      );
    } else {
      _saveToSupabase();
    }
  }

  Future<void> _saveToSupabase() async {
    setState(() => _isLoading = true);
    try {
      String? oneSignalId;
      if (Platform.isAndroid || Platform.isIOS) {
        oneSignalId = OneSignal.User.pushSubscription.id;
      }

      final user = Supabase.instance.client.auth.currentUser;

      await Supabase.instance.client.from('price_alerts').insert({
        'user_id': user!.id,
        'email': user.email,
        'symbol': _selectedSymbol,
        'min_price': double.tryParse(_minCtrl.text) ?? 0,
        'max_price': double.tryParse(_maxCtrl.text) ?? 0,
        'telegram_chat_id': _teleCtrl.text.isNotEmpty ? _teleCtrl.text : null,
        'onesignal_id': oneSignalId,
        'expiry_date': _selectedDate.toIso8601String(),
        'status': 'PENDING',
        'is_active': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Đã tạo cảnh báo thành công!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _showErrorDialog('Lỗi lưu: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Lỗi"),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Đóng"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tạo Cảnh Báo Mới")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _selectedSymbol,
              decoration: const InputDecoration(labelText: "Chọn loại tài sản", border: OutlineInputBorder()),
              items: _symbols.map((symbol) {
                return DropdownMenuItem(value: symbol, child: Text(symbol));
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedSymbol = val!;
                  _currentPrice = 0;
                });
                _fetchCurrentPrice(isBackground: false);
              },
            ),
            const SizedBox(height: 10),

            // HIỂN THỊ GIÁ
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: _isFetchingPrice
                  ? const Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(
                children: [
                  Text("Giá $_selectedSymbol hiện tại:", style: const TextStyle(fontSize: 14)),
                  // Hiển thị giá to rõ
                  Text(
                    "$_currentPrice USD",
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                  // Thêm dòng thông báo tự động cập nhật
                  const SizedBox(height: 5),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh, size: 12, color: Colors.grey),
                      SizedBox(width: 4),
                    ],
                  )
                ],
              ),
            ),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Giá Sàn (Min)", border: OutlineInputBorder(), hintText: "< Giá hiện tại"),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: TextField(
                    controller: _maxCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Giá Trần (Max)", border: OutlineInputBorder(), hintText: "> Giá hiện tại"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            TextField(controller: _teleCtrl, decoration: const InputDecoration(labelText: "Telegram ID (Tùy chọn)", border: OutlineInputBorder())),
            const SizedBox(height: 20),

            ListTile(
              title: Text("Hết hạn: ${DateFormat('dd/MM/yyyy HH:mm').format(_selectedDate)}"),
              subtitle: const Text("(Tối thiểu 24h kể từ bây giờ)", style: TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: const Icon(Icons.calendar_today),
              shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.grey), borderRadius: BorderRadius.circular(5)),
              onTap: () async {
                final date = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime.now(), lastDate: DateTime(2030));
                if (date != null) {
                  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_selectedDate));
                  if (time != null) {
                    setState(() {
                      _selectedDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                    });
                  }
                }
              },
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSave,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("LƯU CẢNH BÁO"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}