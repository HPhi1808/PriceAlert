class PriceAlert {
  final String? id;
  final String symbol;
  final double? minPrice;
  final double? maxPrice;
  final String status;
  final DateTime expiryDate;

  PriceAlert({
    this.id,
    required this.symbol,
    this.minPrice,
    this.maxPrice,
    required this.status,
    required this.expiryDate,
  });

  factory PriceAlert.fromJson(Map<String, dynamic> json) {
    return PriceAlert(
      id: json['id'],
      symbol: json['symbol'] ?? 'BTCUSDT',
      minPrice: json['min_price'] != null ? double.parse(json['min_price'].toString()) : null,
      maxPrice: json['max_price'] != null ? double.parse(json['max_price'].toString()) : null,
      status: json['status'] ?? 'PENDING',
      expiryDate: DateTime.parse(json['expiry_date']),
    );
  }
}