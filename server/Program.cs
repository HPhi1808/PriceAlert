using System.Net;
using System.Net.Mail;
using DotNetEnv;
using Supabase;
using Postgrest.Attributes;
using Postgrest.Models;
using Newtonsoft.Json;

ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls13;
// --- 1. KHỞI TẠO MÔI TRƯỜNG ---
Env.Load();
var sbUrl = Environment.GetEnvironmentVariable("SUPABASE_URL");
var sbKey = Environment.GetEnvironmentVariable("SUPABASE_KEY");
var resendKey = Environment.GetEnvironmentVariable("RESEND_API_KEY");

if (string.IsNullOrEmpty(sbUrl) || string.IsNullOrEmpty(resendKey))
{
    Console.WriteLine("❌ LỖI: Chưa điền đủ thông tin trong file .env");
    return;
}

ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls13;

// Khởi tạo Supabase Client
var options = new SupabaseOptions { AutoRefreshToken = true, AutoConnectRealtime = true };
var supabase = new Client(sbUrl, sbKey, options);
await supabase.InitializeAsync();

Console.WriteLine("✅ Đã kết nối Supabase & Sẵn sàng quét giá!");

// --- 2. TẠO WEB SERVER GIẢ (Để Render không tắt App) ---
var builder = WebApplication.CreateBuilder(args);
var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";
var app = builder.Build();
app.MapGet("/", () => "Worker C# is running...");
_ = app.RunAsync($"http://0.0.0.0:{port}");

// --- 3. VÒNG LẶP WORKER ---
while (true)
{
    try
    {
        Console.WriteLine($"\n[{DateTime.Now:HH:mm:ss}] ⏳ Quét lệnh...");

        // B1. Lấy TẤT CẢ lệnh đang chờ
        var response = await supabase.From<PriceAlert>()
                                     .Select("*")
                                     .Filter("is_active", Postgrest.Constants.Operator.Equals, "true")
                                     .Filter("status", Postgrest.Constants.Operator.Equals, "PENDING")
                                     .Get();

        var alerts = response.Models;

        // B2. Lấy danh sách các cặp tiền cần check (Distinct)
        var uniqueSymbols = alerts.Select(a => a.Symbol).Distinct().ToList();

        if (uniqueSymbols.Count == 0)
        {
            Console.WriteLine("💤 Không có lệnh nào cần xử lý.");
        }

        // B3. Duyệt từng Symbol để lấy giá và so sánh
        foreach (var symbol in uniqueSymbols)
        {
            // Lấy giá của Symbol này (Dynamic URL)
            decimal currentPrice = await GetCryptoPrice(symbol);
            if (currentPrice == 0) continue;

            Console.WriteLine($"💰 {symbol}: {currentPrice} USD");

            // Lọc ra các lệnh thuộc Symbol này để check
            var alertsForSymbol = alerts.Where(a => a.Symbol == symbol).ToList();

            foreach (var alert in alertsForSymbol)
            {
                if (alert.ExpiryDate < DateTime.UtcNow) continue;

                bool isTriggered = false;
                string type = "";

                if (alert.MinPrice > 0 && currentPrice <= alert.MinPrice)
                {
                    isTriggered = true;
                    type = $"Giá {symbol} đã chạm ngưỡng {alert.MinPrice:#,##0.##}";
                }
                else if (alert.MaxPrice > 0 && currentPrice >= alert.MaxPrice)
                {
                    isTriggered = true;
                    type = $"Giá {symbol} đã chạm ngưỡng {alert.MaxPrice:#,##0.##}";
                }

                if (isTriggered)
                {
                    Console.WriteLine($"🔥 Trigger {symbol} cho: {alert.Email}");

                    SendEmail(alert.Email!, type, currentPrice, symbol, resendKey!);

                    // Update DB
                    await supabase.From<PriceAlert>()
                                  .Where(x => x.Id == alert.Id)
                                  .Set(x => x.Status, "SENT")
                                  .Set(x => x.IsActive, false)
                                  .Update();
                }
            }
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"❌ Lỗi: {ex.Message}");
    }

    await Task.Delay(10000);
}

// --- CÁC HÀM HỖ TRỢ ---

// 1. Hàm lấy giá
async Task<decimal> GetCryptoPrice(string rawSymbol)
{
    // 1. Xử lý tên Symbol: BTCUSDT -> BTC
    string symbol = rawSymbol.Replace("USDT", "").ToUpper();

    // --- ƯU TIÊN 1: COINBASE ---
    try
    {
        using var client = new HttpClient();
        client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0");

        // URL Coinbase: https://api.coinbase.com/v2/prices/BTC-USD/spot
        var url = $"https://api.coinbase.com/v2/prices/{symbol}-USD/spot";

        var json = await client.GetStringAsync(url);

        // Cấu trúc JSON: {"data":{"base":"BTC","currency":"USD","amount":"89320.50"}}
        dynamic? data = JsonConvert.DeserializeObject(json);
        string priceStr = data?.data?.amount;

        if (decimal.TryParse(priceStr, out decimal price))
        {
            return price;
        }
    }
    catch (Exception ex)
    {
        // Console.WriteLine($"⚠️ Coinbase lỗi: {ex.Message}");
    }

    // --- ƯU TIÊN 2: BINANCE US ---
    try
    {
        using var client = new HttpClient();
        client.DefaultRequestHeaders.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue
        {
            NoCache = true,
            NoStore = true
        };

        var url = $"https://api.binance.us/api/v3/ticker/price?symbol={rawSymbol}&rand={Guid.NewGuid()}";

        var json = await client.GetStringAsync(url);
        dynamic? data = JsonConvert.DeserializeObject(json);

        if (data?.price != null) return (decimal)data.price;
    }
    catch
    {
        Console.WriteLine("❌ Cả Coinbase và Binance đều lỗi mạng!");
    }

    return 0;
}

// 2. Hàm gửi Email qua Resend SMTP
void SendEmail(string toEmail, string type, decimal price, string symbol, string apiKey)
{
    try
    {
        // Resend SMTP Configuration
        var smtpClient = new SmtpClient("smtp.resend.com")
        {
            Port = 587,
            Credentials = new NetworkCredential("resend", apiKey),
            EnableSsl = true,
            DeliveryMethod = SmtpDeliveryMethod.Network,
            UseDefaultCredentials = false,
            Timeout = 10000
        };

        var mailMessage = new MailMessage
        {
            From = new MailAddress("noreply@uth.asia", "Price Alert System"),
            Subject = $"🚨 {symbol} Biến Động: {type}",
            Body = $"<h1>Giá {symbol}: ${price}</h1><p>Trạng thái: {type}</p>",
            IsBodyHtml = true,
        };

        mailMessage.To.Add(toEmail);
        smtpClient.Send(mailMessage);

        Console.WriteLine($"📧 [SMTP] Đã gửi thành công tới {toEmail}");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"❌ Lỗi SMTP: {ex.Message}");
        if (ex.InnerException != null)
        {
            Console.WriteLine($"   Chi tiết: {ex.InnerException.Message}");
        }
    }
}

// --- MODEL ---
[Table("price_alerts")]
public class PriceAlert : BaseModel
{
    [Column("id")] public string? Id { get; set; }
    [Column("email")] public string? Email { get; set; }
    [Column("symbol")] public string Symbol { get; set; } = "BTCUSDT";
    [Column("min_price")] public decimal MinPrice { get; set; }
    [Column("max_price")] public decimal MaxPrice { get; set; }
    [Column("is_active")] public bool IsActive { get; set; }
    [Column("status")] public string? Status { get; set; }
    [Column("expiry_date")] public DateTime ExpiryDate { get; set; }
}