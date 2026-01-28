LINK: https://github.com/HPhi1808/PriceAlert.git
# 🚀 PriceAlert System - Hệ thống Cảnh báo Giá Crypto
Hệ thống theo dõi giá tiền điện tử (Crypto) và gửi cảnh báo qua Email/Notification khi giá chạm ngưỡng thiết lập. Dự án bao gồm:

Mobile App (Flutter): Giao diện người dùng để đặt lệnh cảnh báo.

Worker Server (C# .NET): Chạy ngầm để quét giá và gửi Email cảnh báo.

## 🛠️ Yêu cầu hệ thống
Trước khi cài đặt, máy tính cần có:

**Flutter SDK (cho App).**

**Android Studio hoặc VS Code.**

**.NET SDK 8.0 trở lên (cho Server).**

**Tài khoản Supabase (Database).**

**Tài khoản Resend (Gửi Email).**

## 📂 Cấu trúc thư mục
PriceAlert/
├── price_alert/            (Source code Flutter)
├── server/                 (Source code C# Worker)
└── README.md
## 📝 Phần 1: Cấu hình Database (Supabase)
Tạo project mới trên Supabase.

Vào phần SQL Editor, chạy đoạn lệnh sau để tạo bảng:

#### SQL

    create table price_alerts (
    id uuid default gen_random_uuid() primary key,
    user_id uuid references auth.users not null,
    email text,
    symbol text not null,
    min_price numeric,
    max_price numeric,
    is_active boolean default true,
    status text default 'PENDING', -- 'PENDING', 'SENT', 'EXPIRED'
    expiry_date timestamptz,
    created_at timestamptz default now(),
    telegram_chat_id text,
    onesignal_id text
    );
Vào **Project Settings** -> **API**, copy **Project URL** và **Service Role Key**

## ⚙️ Phần 2: Cài đặt Server (C# Worker)
Server chịu trách nhiệm quét giá thị trường và gửi mail.

**1. Cấu hình môi trường**
Vào thư mục server/, tạo file .env (không có tên, chỉ có đuôi .env) và điền thông tin:

**Server/.env**

    SUPABASE_URL=https://your-project-id.supabase.co
    SUPABASE_KEY=your-supabase-service-role-key
    RESEND_API_KEY=re_123456_your_resend_key
    PORT=8080
(Lưu ý: RESEND_API_KEY lấy tại Resend.com)

**2. Chạy Server**
Mở Terminal tại thư mục server/ và chạy lệnh:

Khôi phục các thư viện

    dotnet restore

Chạy server

    dotnet run
✅ Thành công: Khi thấy dòng chữ: ✅ Đã kết nối Supabase & Sẵn sàng quét giá!

## 📱 Phần 3: Cài đặt Mobile App (Flutter)
**1. Cấu hình môi trường**
Vào thư mục price_alert/, tạo file .env
**price_alert/.env**

    SUPABASE_URL=https://your-project-id.supabase.co
    SUPABASE_KEY=your-supabase-anon-key
**2. Cấu hình Firebase (Cho Android)**
Để chạy được trên Android, bạn cần file google-services.json:

Vào Firebase Console, tạo project.

Thêm ứng dụng Android với Package Name (tìm trong android/app/build.gradle, thường là com.example.price_alert).

Tải file google-services.json về.

Copy file đó vào thư mục: price_alert/android/app/google-services.json.

**3. Chạy App**

Mở Terminal tại thư mục price_alert/ và chạy:
Tải thư viện

    flutter pub get

Chạy ứng dụng

    flutter run