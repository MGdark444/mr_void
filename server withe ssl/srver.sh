#!/bin/bash
# nginx_setup_v4_1.sh
# النسخة 4.1: إدارة Nginx متقدمة — إعداد دومين/تشغيل/إيقاف/إعادة تحميل/حالة/تنظيف

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
END="\e[0m"

print_header() {
    clear
    echo -e "${GREEN}==============================================="
    echo -e "        🟢 سكربت Nginx الإصدار 4.1 🟢"
    echo -e "===============================================${END}"
}

pause() { read -p "اضغط Enter للعودة للقائمة..."; }

clean_broken_links() {
    echo -e "${YELLOW}[CHECK] فحص الروابط التالفة في /etc/nginx/sites-enabled ...${END}"
    local found=0
    for f in /etc/nginx/sites-enabled/*; do
        [ -e "$f" ] || continue
        if [ -L "$f" ] && [ ! -e "$f" ]; then
            echo -e "${RED}[FOUND] رابط تالف: $f → حذف...${END}"
            sudo rm -f "$f"
            found=1
        fi
    done
    if [ "$found" -eq 0 ]; then
        echo -e "${GREEN}[OK] لا توجد روابط تالفة.${END}"
    else
        echo -e "${GREEN}[OK] تمت إزالة الروابط التالفة.${END}"
    fi
}

server_status() {
    local s
    s=$(systemctl is-active nginx 2>/dev/null || echo "unknown")
    if [ "$s" == "active" ]; then
        echo -e "${GREEN}Nginx: Active (running)${END}"
    elif [ "$s" == "inactive" ]; then
        echo -e "${YELLOW}Nginx: Inactive${END}"
    elif [ "$s" == "failed" ]; then
        echo -e "${RED}Nginx: Failed${END}"
    else
        echo -e "${CYAN}Nginx: $s${END}"
    fi
    echo ""
}

start_server() {
    echo -e "${BLUE}[INFO] تشغيل Nginx...${END}"
    sudo systemctl enable --now nginx
    sudo systemctl restart nginx
    echo -e "${GREEN}[OK] تم تشغيل/إعادة تشغيل Nginx.${END}"
}

stop_server() {
    echo -e "${RED}[INFO] إيقاف Nginx...${END}"
    sudo systemctl stop nginx
    sudo systemctl disable nginx
    echo -e "${GREEN}[OK] تم إيقاف Nginx (مع تعطيل التشغيل التلقائي).${END}"
}

reload_server() {
    echo -e "${BLUE}[INFO] إعادة تحميل إعدادات Nginx (reload)...${END}"
    if sudo nginx -t; then
        sudo systemctl reload nginx
        echo -e "${GREEN}[OK] تم إعادة تحميل Nginx بنجاح.${END}"
    else
        echo -e "${RED}[ERROR] فشل الاختبار: لا تقم بالـ reload. افحص الإعدادات أولاً.${END}"
        sudo nginx -t
    fi
}

stop_conflicting_services() {
    echo -e "${YELLOW}[INFO] فحص وإيقاف أي خدمات قد تمنع Nginx من الاستماع على البورت المختار...${END}"
    for svc in apache2 httpd python python3; do
        if pgrep -x $svc >/dev/null 2>&1; then
            echo -e "${RED}[INFO] تم العثور على خدمة تعمل: $svc → سيتم إيقافها${END}"
            sudo pkill -f $svc
        fi
    done
    sudo fuser -k "$listen_port"/tcp >/dev/null 2>&1 || true
}

setup_domain() {
    clean_broken_links

    read -p "➡ أدخل اسم الدومين (مثال: example.com): " domain
    domain="${domain,,}"

    config_avail="/etc/nginx/sites-available/$domain"
    config_enabled="/etc/nginx/sites-enabled/$domain"

    if [ -f "$config_avail" ]; then
        echo -e "${YELLOW}[WARN] يوجد ملف إعداد سابق: $config_avail${END}"
        echo "1) استبدال الملف (Backup ثم إنشاء جديد)"
        echo "2) استخدام الملف القديم كما هو (لا تعديل)"
        echo "3) تعديل المسار/الشهادة ولكن الاحتفاظ بنسخة احتياطية"
        echo "4) إلغاء"
        read -p "➡ اختر رقم: " dom_choice
        case "$dom_choice" in
            1)
                sudo cp "$config_avail" "${config_avail}.bak.$(date +%Y%m%d%H%M%S)"
                sudo rm -f "$config_avail" "$config_enabled"
                echo -e "${GREEN}[OK] تم أخذ نسخة احتياطية وحذف القديم.${END}";;
            2)
                echo -e "${GREEN}[OK] سيتم استخدام الملف القديم كما هو.${END}"
                if [ ! -L "$config_enabled" ]; then
                    sudo ln -s "$config_avail" "$config_enabled"
                    echo -e "${GREEN}[OK] تم تفعيل الموقع.${END}"
                fi
                reload_server
                return 0;;
            3)
                sudo cp "$config_avail" "${config_avail}.bak.$(date +%Y%m%d%H%M%S)"
                sudo rm -f "$config_enabled"
                echo -e "${GREEN}[OK] النسخة الاحتياطية تمت؛ سننشئ إعداد جديد الآن.${END}";;
            *) echo "تم الإلغاء."; return 0;;
        esac
    fi

    read -p "➡ أدخل مسار ملفات الموقع (مثال: /var/www/): " webroot
    webroot="${webroot%/}/"

    if [ ! -f "${webroot}index.html" ]; then
        echo -e "${RED}[ERROR] ملف index.html غير موجود في ${webroot}${END}"
        read -p "هل تريد إنشاء index.html تجريبي هنا؟ (y/n): " createindex
        if [[ "$createindex" == "y" ]]; then
            sudo mkdir -p "$webroot"
            echo "<html><body><h1>It works: $domain</h1></body></html>" | sudo tee "${webroot}index.html" >/dev/null
            echo -e "${GREEN}[OK] تم إنشاء index.html تجريبي.${END}"
        else
            echo -e "${RED}أوقف التنفيذ وأضف index.html ثم أعد المحاولة.${END}"
            return 1
        fi
    fi

    read -p "➡ أدخل بورت الاستماع لـ HTTPS (افتراضي: 443): " listen_port
    listen_port="${listen_port:-443}"

    stop_conflicting_services

    read -p "➡ أدخل مسار fullchain.pem (أو اكتب 'self' لإنشاء شهادة Self-signed): " fullchain
    if [ "$fullchain" == "self" ]; then
        sudo mkdir -p /etc/ssl/$domain
        fullchain="/etc/ssl/$domain/fullchain.pem"
        privkey="/etc/ssl/$domain/privkey.pem"
        echo -e "${YELLOW}[INFO] إنشاء شهادة Self-signed لمجال $domain ...${END}"
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$privkey" -out "$fullchain" -subj "/CN=$domain" >/dev/null 2>&1
        echo -e "${GREEN}[OK] شهادة Self-signed أنشئت في /etc/ssl/$domain/${END}"
    else
        read -p "➡ أدخل مسار privkey.pem: " privkey
    fi

    if [ ! -f "$fullchain" ] || [ ! -f "$privkey" ]; then
        echo -e "${RED}[ERROR] ملفات الشهادة غير موجودة.${END}"
        return 1
    fi

    echo -e "${BLUE}[INFO] إنشاء ملف إعداد Nginx: $config_avail${END}"

    sudo tee "$config_avail" > /dev/null <<EOF
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen $listen_port ssl ;
    http2 on;
    server_name $domain;

    ssl_certificate $fullchain;
    ssl_certificate_key $privkey;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root $webroot;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    client_max_body_size 50M;
}
EOF

    sudo ln -sf "$config_avail" "$config_enabled"
    echo -e "${GREEN}[OK] تم تفعيل الملف (symlink)${END}"

    echo -e "${BLUE}[INFO] اختبار إعداد Nginx...${END}"
    if sudo nginx -t; then
        echo -e "${GREEN}[OK] اختبار صحيح.${END}"
        read -p "➡ هل تريد تمكين الموقع الآن وتشغيل Nginx؟ (y/n): " runnow
        if [[ "$runnow" == "y" ]]; then
            sudo ufw allow 80/tcp
            sudo ufw allow "$listen_port"/tcp
            sudo ufw --force enable
            start_server
            echo -e "${GREEN}🌍 افتح موقعك الآن: https://$domain${END}"
            read -p "هل تستخدم نفق (Playit/Portmap)؟ اذا نعم اكتب البورت وإلا اترك فارغ: " extport
            if [ -n "$extport" ]; then
                echo -e "${GREEN}🌍 مع البورت: https://$domain:$extport${END}"
            fi
        else
            echo -e "${YELLOW}توقف — الموقع مهيأ ولكن لم يتم تشغيله.${END}"
        fi
    else
        echo -e "${RED}[ERROR] فشل اختبار nginx -t. راجع الملف: $config_avail${END}"
        sudo nginx -t
        return 1
    fi
}

while true; do
    print_header
    echo -e "${CYAN}الحالة الحالية:${END}"
    server_status
    echo -e "${YELLOW}اختر خياراً:${END}"
    echo "1) إعداد دومين جديد / تعديل إعداد موجود"
    echo "2) تشغيل السيرفر (start + restart)"
    echo "3) إيقاف السيرفر (stop + disable)"
    echo "4) إعادة تحميل الإعدادات (reload)"
    echo "5) تنظيف الروابط التالفة"
    echo "6) عرض ملفات sites-available و sites-enabled"
    echo "7) خروج"
    read -p "➡ اختر رقم: " choice

    case "$choice" in
        1) setup_domain; pause ;;
        2) start_server; pause ;;
        3) stop_server; pause ;;
        4) reload_server; pause ;;
        5) clean_broken_links; pause ;;
        6)
            echo -e "${BLUE}--- sites-available ---${END}"
            ls -la /etc/nginx/sites-available || echo "لا يوجد وصول"
            echo -e "${BLUE}--- sites-enabled ---${END}"
            ls -la /etc/nginx/sites-enabled || echo "لا يوجد وصول"
            pause
            ;;
        7) echo "خروج..."; exit 0 ;;
        *) echo -e "${RED}خيار غير صحيح.${END}"; sleep 1 ;;
    esac
done
