# KAJ ERP — التطوير المحلي على Windows وVS Code

هذا المسار مخصص للتطوير المحلي فقط. أثناء استخدامه يجب أن يتصل KAJ ERP بـ Supabase المحلي على `127.0.0.1` فقط، ولا يحتاج إلى تسجيل دخول إلى حساب Supabase Hosted.

## 1. تجهيز WSL 2 مرة واحدة

افتح VS Code بصلاحية Administrator، ثم افتح Terminal من داخل VS Code وشغّل PowerShell:

```powershell
wsl --install
```

إذا كان WSL مثبتاً مسبقاً:

```powershell
wsl --update
wsl --version
wsl -l -v
```

إذا طلب Windows إعادة التشغيل، أعد تشغيل الجهاز ثم أكمل الخطوات التالية.

## 2. تثبيت Docker Desktop من Terminal داخل VS Code

بعد تشغيل Windows من جديد، افتح VS Code وPowerShell وشغّل:

```powershell
winget search --id Docker.DockerDesktop -e
winget install --id Docker.DockerDesktop -e --accept-package-agreements --accept-source-agreements
```

إذا تعذر التثبيت عبر `winget`، ثبّت Docker Desktop بواسطة المثبت الرسمي من Docker واختر WSL 2 backend.

بعد التثبيت افتح Docker Desktop مرة واحدة واترك Linux containers / WSL 2 backend مفعلاً.

تحقق من أن المحرك يعمل:

```powershell
docker version
docker info
```

إضافة VS Code المسماة **Container Tools** مفيدة لإدارة الحاويات من داخل VS Code، لكنها ليست بديلاً عن Docker Desktop نفسه.

## 3. فتح الفرع الصحيح

من Terminal داخل مجلد المشروع:

```powershell
git fetch origin
git checkout antigravity/r86-final-audit-20260816
git pull --ff-only
```

## 4. أول تجهيز محلي من VS Code

من VS Code:

1. افتح Command Palette بواسطة `Ctrl+Shift+P`.
2. اختر `Tasks: Run Task`.
3. اختر `KAJ: Local Setup (first run)`.

المهمة تقوم تلقائياً بما يلي:

- التحقق من Git وNode وPython وFlutter وDocker.
- التحقق أن Docker Engine يعمل.
- تثبيت أدوات المشروع المقيّدة في `package-lock.json` بواسطة `npm ci` عند الحاجة، بما فيها Supabase CLI المحلية.
- تشغيل Supabase المحلي فقط.
- أخذ نسخة احتياطية محلية قبل تحديث migrations الموجودة.
- تطبيق migrations محلياً بطريقة forward-only بدون `db reset` وبدون `db push` إلى Hosted.
- إنشاء/تحديث مستخدم Auth محلي للتطوير.
- ربط المستخدم المحلي بالشركة المحلية كـ owner/system admin.
- التحقق من أن عقد Local/Production لا يسمح بالانتقال الصامت بين البيئتين.

يمكن تنفيذ نفس الخطوة من Terminal مباشرة:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\setup_local_development.ps1
```

## 5. بيانات الدخول المحلية الافتراضية

```text
Email:    dev@kaj.local
Password: KajLocalDev!2026-LocalOnly
```

هذه بيانات تطوير محلية فقط، ولا تُنشأ في Production.

لتحديد كلمة مرور محلية مختلفة أثناء التجهيز:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\setup_local_development.ps1 `
  -Email "dev@kaj.local" `
  -Password "ضع-هنا-كلمة-مرور-محلية"
```

## 6. تشغيل KAJ ERP محلياً

من VS Code:

1. `Ctrl+Shift+P`
2. `Tasks: Run Task`
3. `KAJ: Local Run`

أو من Terminal:

```powershell
npm run run:web:local
```

المشغل يتحقق أولاً من source/database contracts، يجهز قاعدة Local الحالية forward-only، ثم يشغّل Flutter Web على Microsoft Edge باستخدام ملف runtime محلي مولّد من Supabase المحلي.

في أول مرة فقط يمكن استخدام المهمة المجمعة:

`KAJ: Local Setup + Run`

## 7. الوصول إلى Supabase المحلي

بعد تشغيل Local Supabase:

```text
API:    http://127.0.0.1:54321
Studio: http://127.0.0.1:54323
```

افتح Studio لمشاهدة PostgreSQL والجداول وAuth وStorage محلياً. عنوان قاعدة PostgreSQL الفعلي يظهر أيضاً في ناتج `supabase status`/سكربت التجهيز.

لرؤية حالة الخدمات من Terminal:

```powershell
npx --no-install supabase status
```

## 8. تسجيل الدخول إلى البرنامج

بعد أن يفتح KAJ ERP في المتصفح، استخدم:

```text
dev@kaj.local
KajLocalDev!2026-LocalOnly
```

الحساب مؤكد محلياً بواسطة Supabase Auth ومربوط ببيانات bootstrap المحلية بصلاحية owner/system admin حتى يمكن اختبار النظام كاملاً.

## 9. إيقاف Supabase المحلي بدون حذف البيانات

من VS Code اختر المهمة:

`KAJ: Stop Local Supabase`

أو من Terminal:

```powershell
npx --no-install supabase stop
```

هذا يوقف الحاويات مع الاحتفاظ ببيانات Local المعتادة.

في يوم العمل التالي لا تحتاج إلى إعادة إنشاء الحساب. شغّل `KAJ: Local Run` وسيقوم مسار التجهيز بتشغيل Local Supabase عند الحاجة وتطبيق أي migrations محلية جديدة forward-only.

## 10. أوامر ممنوعة في مسار التطوير العادي

لا تستخدم أثناء التطوير المحلي:

```text
supabase link <old-project>
supabase db push --linked
supabase stop --no-backup
supabase db reset
```

إلا إذا كان هناك إجراء مقصود ومراجع لحالة خاصة. مسار التشغيل العادي لا يحتاج إلى `supabase login` ولا إلى ربط أي Hosted project.

## 11. Production منفصل

Production ليس جزءاً من هذا المسار. المرجع الوحيد المسموح به في عقد Production هو:

```text
havlqebmnjdcwmpaaqew
```

ولا يجوز نقل migrations أو Auth أو Storage أو بيانات إليه من مسار Local تلقائياً.
