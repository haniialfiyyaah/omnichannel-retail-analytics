# Naskah presentasi

10–15 menit, termasuk pertanyaan. Bicara sekitar 6 menit. Demo sekitar 3 menit. Sisanya untuk pertanyaan.

Kalau slot hanya 10 menit, lewati riwayat profil dan hari inventory yang hilang di slide 5. Tetap sebut order duplikat dan produk yang tidak ada.

Siapkan ini sebelum mulai:

| Siap | Di mana |
| --- | --- |
| Slide | Presentasi ini |
| Airflow | [localhost:8080](http://localhost:8080) — run hijau `retail_analytics_pipeline` — login `admin` / `admin` |
| UI | [localhost:8501](http://localhost:8501) |
| Cadangan | `evidence/airflow_run.png` kalau DAG live lambat |

| Slide | Waktu | Yang disampaikan |
| --- | --- | --- |
| 1 Judul | 20 dtk | Latar belakang: apa yang dibangun |
| 2 Masalah | 30 dtk | Mengapa Gold yang salah tetap berbahaya |
| 3 Alur | 25 dtk | Satu kali menyusuri diagram |
| 4 Airflow | 40 dtk | Tujuh task, dan gate yang gagal menghentikan Gold |
| 5 Pembersihan | 40 dtk | Pemenang tetap, yang kalah dicatat |
| 6 Pengecekan | 45 dtk | Tiga cek sebelum Gold, enam sesudahnya |
| 7 Gold | 35 dtk | Lima grain dan rumus net revenue |
| 8 Demo | 3 mnt | DAG hijau, lalu satu pertanyaan |
| 9 Evaluasi | 40 dtk | Batas refund, lalu aturan yang tidak tertulis di brief |
| 10 Penutup | 30 dtk | Poin utama, lalu empat detail |

---

## 1 · Judul

**Latar belakang · 20 detik**

> Saya membangun jalur data untuk retailer omnichannel. Order, pembayaran, refund, inventory, dan pengeluaran campaign berawal dari file mentah. File itu berakhir di Gold pada PostgreSQL. Engine NL-to-SQL dan UI sudah disediakan. Saya tidak membangun ulang keduanya.

Berdiri di slide ini. Jangan buka demo dulu.

---

## 2 · Masalah

**Permasalahan · 30 detik**

> File-nya berantakan: order duplikat, pembayaran terpecah, refund sebagian, timezone campur, produk yang tidak ada, dan hari inventory yang tidak pernah datang. Engine tidak pernah melihat Bronze atau Silver. Kalau Gold salah, UI tetap menampilkan chart, dan chart itu salah. Pipeline ini ada supaya chart sesuai dengan sumbernya.

Tunjuk baris ketiga saat mengatakan chart-nya bisa salah.

---

## 3 · Alur

**25 detik**

> File mentah masuk ke Bronze tanpa diubah. Silver memberi tipe, menyimpan satu pemenang untuk duplikat, dan mencatat yang kalah beserta alasannya. Quality gate memeriksa Silver dan bisa menghentikan Gold. Gold membangun lima tabel. Validate Gold membandingkan total di Silver dengan nilai di Gold. Baru setelah itu UI mengajukan pertanyaan.

Gerakkan tangan sekali sepanjang diagram. Jangan jelaskan setiap tabel dulu.

---

## 4 · Task Airflow

**40 detik**

> Airflow menjalankan tujuh task ini dari `dags/dag.py`. Setiap task menunggu task di atasnya selesai. `load_bronze` membuat satu `pipeline_run_id` untuk seluruh run. Kalau gate Silver gagal, Gold tidak dibangun. `validate_gold` harus berjalan setelah Gold, karena ia membandingkan total Silver dengan nilai Gold. Tabel Gold yang kosong akan membuat cek itu gagal. Trigger kedua memakai run id baru dan mengganti setiap layer. Ia tidak menambahkan salinan.

Kalau ada gambar di sudut, tunjuk `quality_gate` lalu `build_gold`. Tetap di slide. Layar Airflow yang live adalah bagian demo.

---

## 5 · Yang dibersihkan

**40 detik**

> Bronze menyimpan setiap record sumber. Silver adalah pembersihannya. Order, event, atau item yang berulang menyimpan satu pemenang. Salinan yang kalah disimpan di `rejected_records` dengan alasan itu. Item dengan quantity negatif, atau produk yang tidak ada di file produk, ditolak dan tidak masuk ke `order_items`. Riwayat profil dan kategori bukan penolakan. Baris itu tetap sebagai versi. Hari inventory yang hilang tidak diisi nol, dan itu juga bukan penolakan.

Tunjuk `duplicate_order_id` dan `missing_product`. Jangan buka database.

Pada slot 10 menit, berhenti setelah produk yang hilang. Lewati riwayat profil dan hari inventory yang hilang.

---

## 6 · Yang dicek

**45 detik**

> Gate sebelum Gold hanya melihat Silver. Ia memeriksa bahwa order sudah ter-load, bahwa order duplikat ditolak, dan bahwa item yang ditolak tidak ada di `order_items`. Ia tidak memeriksa ulang setiap alasan penolakan. Kalau gate ini gagal, Gold tidak dibangun. Setelah Gold ada, lima cek membandingkan total Silver dengan nilai Gold: jumlah order, net revenue, refund yang selesai, pembayaran yang captured, dan revenue item. Cek keenam, total order harian, membandingkan dua angka Gold. Keenam cek itu tidak bisa dijalankan lebih dulu. Tabel Gold yang kosong akan membuat cek jumlah order gagal.

Tunjuk kelompok sebelum Gold, lalu kelompok sesudah Gold.

---

## 7 · Gold

**35 detik**

> Gold hanya membaca Silver. Setiap tabel punya satu grain. Uang dijumlahkan ke grain itu sebelum join apa pun, supaya promotion atau campaign tidak menggandakan revenue. Diskon di net revenue hanya total promotion. Hanya refund yang selesai yang mengurangi nilainya. `executive_kpis_daily` membaca tabel Gold yang lain. Ia tidak menjumlahkan event mentah lagi.

Tunjuk rumusnya, lalu `executive_kpis_daily`.

---

## 8 · Demo

**3 menit**

> Saya tunjukkan satu run yang sudah selesai, lalu satu pertanyaan ke Gold lokal.

1. Pindah ke Airflow. Tunjukkan `retail_analytics_pipeline` dengan ketujuh task hijau. Sebut nama `quality_gate` dan `validate_gold` sambil menunjuknya. Kalau layar lambat, pakai `evidence/airflow_run.png`.
2. Pindah ke [localhost:8501](http://localhost:8501).
3. Tanyakan persis: `Show me net revenue trend for the last 30 days`
4. Tunggu chart dan tabelnya.
5. Buka **Show SQL and provenance** dan bacakan `gold.executive_kpis_daily`.
6. Katakan: query ini tidak menyentuh Bronze atau Silver.

Kembali ke slide. Jangan ajukan pertanyaan kedua kecuali ada yang memintanya.

---

## 9 · Evaluasi

**40 detik**

> Ini batas yang akan saya perbaiki berikutnya. Event refund tidak membawa product id, jadi saya tidak tahu item mana yang di-refund. Di `product_daily`, refunded units adalah quantity produk itu pada order yang punya refund selesai. Kalau satu order punya dua produk dan hanya satu yang di-refund, kedua produk bisa tampak ter-refund. Total refund di level order pada `order_360` tetap sebesar refund yang selesai. Titik lemahnya ada di pembagian per produk.

> Bagian yang sulit adalah aturan yang tidak ditulis di brief. Kontrak Gold menetapkan nama tabel, grain, dan net revenue. Kontrak itu tidak mengatakan salinan mana yang menang kalau order berulang, apakah hari inventory yang hilang diisi nol, atau apakah riwayat profil adalah duplikat. Saya membaca file mentah dan memilih aturan itu. Setiap run memakai aturan yang sama. Berikutnya saya akan menaruh product id pada refund, supaya `product_daily` bisa membagi refund sebagian, bukan menandai setiap produk pada order itu. Saya juga akan menambah cek untuk kasus yang file ini tidak miliki, misalnya order tanpa customer atau jam yang tidak bisa dibaca. Pada extract ini, cek itu tidak akan menolak apa pun.

Tetap di slide. Jangan buka SQL. Tunjuk baris refund, lalu dua cue.

---

## 10 · Penutup

**30 detik**

> Chart sesuai dengan sumbernya. Bronze menyimpan setiap record mentah. Silver menyimpan satu pemenang dan mencatat yang kalah. Gold menjumlahkan uang sebelum join apa pun. Pengecekan membandingkan total Silver dengan nilai Gold sebelum ada yang bertanya. Saya siap menerima pertanyaan.

Tunjuk poin utama, lalu turun ke empat detail.

Berhenti membagikan demo. Biarkan slide ini tetap terbuka untuk pertanyaan.
