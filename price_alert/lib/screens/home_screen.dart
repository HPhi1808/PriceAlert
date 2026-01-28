import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/price_alert_model.dart';
import 'create_alert_screen.dart';
import 'auth_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Stream<List<Map<String, dynamic>>> _alertsStream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _alertsStream = Supabase.instance.client
        .from('price_alerts')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false);
  }

  Future<void> _deleteAlert(String id) async {
    try {
      await Supabase.instance.client.from('price_alerts').delete().eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa lệnh.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xóa: $e')));
      }
    }
  }

  Future<void> _handleLogout() async {
    try {
      const storage = FlutterSecureStorage();
      await storage.deleteAll();
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AuthScreen()),
                (route) => false
        );
      }
    } catch (e) {
      debugPrint("Lỗi đăng xuất: $e");
    }
  }

  Map<String, dynamic> _getStatusDisplay(String status, DateTime expiryDate) {
    bool isExpired = DateTime.now().isAfter(expiryDate) && status == 'PENDING';

    if (status == 'SENT') {
      return {
        'text': 'Đã gửi',
        'color': Colors.green.shade700,
        'bg': Colors.green.shade50
      };
    } else if (isExpired) {
      return {
        'text': 'Hết hạn',
        'color': Colors.grey.shade700,
        'bg': Colors.grey.shade200
      };
    } else {
      return {
        'text': 'Đang chờ',
        'color': Colors.orange.shade800,
        'bg': Colors.orange.shade50
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Danh Sách Cảnh Báo"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateAlertScreen()),
          );
          setState(() {
            _initStream();
          });
        },
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _alertsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Lỗi tải dữ liệu: ${snapshot.error}"));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Stack(
              children: [
                const Center(child: Text("Bạn chưa có cảnh báo nào.\nHãy bấm dấu + để tạo mới.", textAlign: TextAlign.center)),
                RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _initStream());
                    await Future.delayed(const Duration(seconds: 1));
                  },
                  child: ListView(physics: const AlwaysScrollableScrollPhysics()),
                )
              ],
            );
          }

          final alerts = snapshot.data!.map((e) => PriceAlert.fromJson(e)).toList();

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _initStream();
              });
              await Future.delayed(const Duration(seconds: 1));
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 80, top: 10),
              itemCount: alerts.length,
              itemBuilder: (context, index) {
                final alert = alerts[index];
                final minPrice = alert.minPrice ?? 0;
                final maxPrice = alert.maxPrice ?? 0;
                final statusInfo = _getStatusDisplay(alert.status, alert.expiryDate);

                return Dismissible(
                  key: Key(alert.id ?? index.toString()),
                  background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white)
                  ),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _deleteAlert(alert.id!),
                  child: Card(
                    color: alert.status == 'SENT' ? Colors.green.shade50.withOpacity(0.3) : Colors.white,
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    elevation: 2,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        child: Text(
                            alert.symbol.isNotEmpty ? alert.symbol.substring(0, 1) : "?",
                            style: const TextStyle(color: Colors.white)
                        ),
                      ),
                      title: Text(alert.symbol, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (minPrice > 0) Text("📉 Báo khi giảm xuống: ${NumberFormat("#,##0.##").format(minPrice)}"),
                          if (maxPrice > 0) Text("📈 Báo khi tăng lên: ${NumberFormat("#,##0.##").format(maxPrice)}"),
                          const SizedBox(height: 4),
                          Text(
                              "⏳ Hết hạn: ${DateFormat('dd/MM HH:mm').format(alert.expiryDate)}",
                              style: const TextStyle(fontSize: 12, color: Colors.grey)
                          ),
                        ],
                      ),
                      trailing: Chip(
                        label: Text(
                          statusInfo['text'],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusInfo['color'],
                          ),
                        ),
                        backgroundColor: statusInfo['bg'],
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}