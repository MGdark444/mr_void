#!/usr/bin/env bash
set -euo pipefail

# ====== الألوان والدوال ======
GREEN="\e[32m"; RED="\e[31m"; YELLOW="\e[33m"; BLUE="\e[34m"; RESET="\e[0m"
ok(){ echo -e "${GREEN}✅ $1${RESET}"; }
warn(){ echo -e "${YELLOW}⚠️ $1${RESET}"; }
err(){ echo -e "${RED}❌ $1${RESET}"; }
info(){ echo -e "${BLUE}[INFO]${RESET} $1"; }

# ====== قراءة المتغيرات ======
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-you@example.com}"
DYNU_CLIENT_ID="${DYNU_CLIENT_ID:-}"
DYNU_SECRET="${DYNU_SECRET:-}"
SSL_DIR="${SSL_DIR:-/etc/ssl/$DOMAIN}"
FORCE="${FORCE:-false}"   # دعم --force

# ====== التحقق من root ======
if [ "$EUID" -ne 0 ]; then
  err "يجب تشغيل السكربت بصلاحيات root"
  exit 1
fi

# ====== التحقق من المتغيرات ======
if [ -z "$DOMAIN" ]; then err "يجب تحديد DOMAIN"; exit 1; fi
if [ -z "$DYNU_CLIENT_ID" ] || [ -z "$DYNU_SECRET" ]; then
  err "يجب إدخال DYNU_CLIENT_ID و DYNU_SECRET"
  exit 1
fi

info "الدومين: $DOMAIN"
info "مسار الشهادة: $SSL_DIR"
info "البريد: $EMAIL"
ok "البيانات جاهزة للبدء"

# ====== تثبيت acme.sh إذا لم يكن موجود ======
if [ ! -d "/root/.acme.sh" ]; then
  info "acme.sh غير مثبت — جاري تثبيته..."
  curl -s https://get.acme.sh | sh -s email="$EMAIL"
  ok "تم تثبيت acme.sh بنجاح"
else
  ok "acme.sh مثبت مسبقًا — تخطي التثبيت"
fi

# ====== تحميل بيانات Dynu ======
export Dynu_ClientId="$DYNU_CLIENT_ID"
export Dynu_Secret="$DYNU_SECRET"

# ====== كشف وجود شهادة قديمة ======
CERT_PATH="/root/.acme.sh/${DOMAIN}/${DOMAIN}.cer"

if [ -f "$CERT_PATH" ]; then
  warn "تم العثور على شهادة موجودة مسبقًا لهذا الدومين"

  if [ "$FORCE" = "true" ]; then
    warn "يتم إعادة الإصدار بالقوة (--force)"
    ISSUE_ARGS="--force"
  else
    warn "إذا تريد إعادة الإصدار بالقوة نفّذ:"
    echo -e "${YELLOW}FORCE=true ./ssl.sh${RESET}"
    ISSUE_ARGS=""
  fi
else
  ISSUE_ARGS=""
fi

# ====== إصدار الشهادة ======
info "جاري إصدار شهادة باستخدام DNS-01 عبر Dynu..."

~/.acme.sh/acme.sh --issue \
  --dns dns_dynu \
  -d "$DOMAIN" \
  --dnssleep 180 \
  $ISSUE_ARGS

ok "تم إصدار الشهادة بنجاح"

# ====== تثبيت الشهادة ======
info "تنصيب الشهادة في $SSL_DIR"
mkdir -p "$SSL_DIR"

~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
  --key-file "$SSL_DIR/privkey.pem" \
  --fullchain-file "$SSL_DIR/fullchain.pem"

ok "تم تثبيت الشهادة بنجاح!"
echo -e "${GREEN}🎉 الشهادة أصبحت جاهزة للاستخدام في Nginx أو أي خدمة أخرى${RESET}"
