# ระบบสต็อกของใช้สำนักงาน (Supabase + git)

แดชบอร์ด เบิก / รับ / สรุป / แก้ไขสต็อก — หน้าเว็บเดี่ยว (`index.html`) คุยกับ Supabase โปรเจกต์ `office-stock` โดยตรง

## โครงสร้าง
- `supabase/migrations/` — schema (ตาราง items, movements, profiles, views, RLS, trigger ตัดสต็อก)
- `scripts/build_seed.py` — แปลงไฟล์ชีต .html เป็น seed.sql (ไฟล์ที่ได้มีข้อมูลบุคคล ห้าม commit: ถูกกันไว้ใน .gitignore)
- `index.html`, `config.js` — หน้าเว็บ (อยู่ที่ root เพื่อให้ GitHub Pages เปิดได้)

## วิธีทำงาน
- ทุกการเบิก/รับ/ปรับยอด = 1 แถวใน `movements`; trigger ปรับ `items.qty` และกันสต็อกติดลบ
- แก้ไขสต็อก = ใส่ยอดที่นับจริง ระบบบันทึก `ADJUST` (ส่วนต่าง + เหตุผล) ไว้ตรวจสอบย้อนหลัง
- ผู้ใช้คนแรกที่สมัครเป็นแอดมินอัตโนมัติ คนถัดไปต้องรอแอดมินอนุมัติในแท็บ "ผู้ใช้"
- เฉพาะแอดมินที่เพิ่ม/แก้สินค้าและปรับยอดได้ (บังคับด้วย RLS ในฐานข้อมูล)

## เริ่มใช้
1. เปิด `index.html` (หรือเปิด GitHub Pages: Settings → Pages → Branch main, โฟลเดอร์ / (root)) → สมัครด้วยอีเมลของแอดมินก่อนเป็นคนแรก
2. Supabase Dashboard → Authentication → ปิด "Allow new users to sign up" (หรือเปิดไว้และอนุมัติทีละคน) และตั้ง Site URL เป็นที่อยู่เว็บจริง
3. ข้อมูลสต็อกและประวัติอยู่ใน Supabase เท่านั้น ไม่ได้เก็บไว้ใน repo นี้
