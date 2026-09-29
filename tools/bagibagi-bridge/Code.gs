// =====================================================================
// HAVN — jembatan donasi bagibagi.co → Roblox (Google Apps Script) — v2
// ---------------------------------------------------------------------
// Pengganti ScriptGas (Bebeq). Sheet & data lama TIDAK diubah: baris baru tetap ditambah
// ke tab "Sheet1" dengan kolom yang sama (ID | Username | Amount | Message | Tanggal | Provider).
//
// PASANG (sekali):
// 1) Google Sheet → Extensions → Apps Script → ganti SELURUH isi Code.gs dengan file ini → Save.
// 2) Project Settings (ikon gerigi) → Script Properties → Add:
//      WEBHOOK_KEY = <acak panjang, untuk bagibagi>
//      READ_KEY    = <acak panjang LAIN, untuk server Roblox>
//    Kunci TIDAK ditulis di kode ini (kode ini ada di repo publik).
// 3) Deploy → Manage deployments → (deployment yang sudah ada) ✏️ Edit → Version: New version → Deploy.
//    URL /exec tetap sama.
// 4) bagibagi → Integrasi Overlay → Custom Webhook → Custom Url:
//      https://script.google.com/macros/s/XXXX/exec?source=bagibagi&key=<WEBHOOK_KEY>
//
// POST (bagibagi):  ?source=bagibagi&key=<WEBHOOK_KEY>, body JSON
//   { transaction_id, name, amount, message, mediaShareUrl, created_at }  (terbukti di tab Logs 2026-09-29)
//   Kunci salah → ditolak. Tanpa transaction_id / amount → ditolak. ID yang sudah ada → tidak ditulis lagi
//   (kecuali ID tes bagibagi, supaya "Send Webhook Test" bisa diulang).
// GET (Roblox):     ?key=<READ_KEY>&after=<nomor baris terakhir yang sudah diambil>
//   → { ok, next, items: [{ row, id, name, amount, message, created, test }] } maksimal MAX_ITEMS baris.
//   Tanpa `after` → { ok, next: <baris terakhir>, items: [] } (titik mulai; riwayat lama tidak dikirim).
// =====================================================================

var SHEET_NAME = "Sheet1";
var LOG_SHEET = "Logs";
var HEADERS = ["ID", "Username", "Amount", "Message", "Tanggal", "Provider"];
var MAX_ITEMS = 20;
var LOG_KEEP = 300; // baris Logs terakhir yang disimpan
var TEST_ID = "bagibagi-965b3d64-1f5e-4361-a01b-5b58df37190c"; // ID tetap tombol "Send Webhook Test" bagibagi

function prop(name) {
  return PropertiesService.getScriptProperties().getProperty(name) || "";
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

function getSheet(name, headers) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(name);
  if (!sh) {
    sh = ss.insertSheet(name);
    if (headers) sh.appendRow(headers);
  }
  return sh;
}

function logRaw(source, raw) {
  try {
    var sh = getSheet(LOG_SHEET, ["date", "source", "raw"]);
    sh.appendRow([new Date(), source, String(raw).slice(0, 2000)]);
    var extra = sh.getLastRow() - 1 - LOG_KEEP;
    if (extra > 0) sh.deleteRows(2, extra);
  } catch (_) {}
}

// Kunci dibanding dengan waktu tetap (tidak berhenti di karakter pertama yang beda).
function sameKey(given, expected) {
  given = String(given || "");
  if (expected.length < 16 || given.length !== expected.length) return false;
  var diff = 0;
  for (var i = 0; i < expected.length; i++) diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

function toAmount(v) {
  if (typeof v === "number") return Math.round(v);
  var n = parseInt(String(v || "").replace(/[^0-9]/g, ""), 10);
  return isNaN(n) ? 0 : n;
}

function clip(s, n) {
  s = String(s === undefined || s === null ? "" : s);
  return s.length > n ? s.slice(0, n) : s;
}

function doPost(e) {
  var raw = e && e.postData && e.postData.contents ? String(e.postData.contents) : "";
  if (!sameKey(e && e.parameter && e.parameter.key, prop("WEBHOOK_KEY"))) {
    logRaw("ditolak:kunci", raw.slice(0, 200));
    return json({ status: "failed", error: "unauthorized" });
  }
  var body;
  try {
    body = JSON.parse(raw);
  } catch (_) {
    body = null;
  }
  var id = body && clip(body.transaction_id, 100);
  var amount = body ? toAmount(body.amount) : 0;
  if (!id || amount <= 0) {
    logRaw("ditolak:isi", raw);
    return json({ status: "failed", error: "invalid" });
  }
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) return json({ status: "failed", error: "busy" }); // bagibagi bisa mengirim ulang
  try {
    var sheet = getSheet(SHEET_NAME, HEADERS);
    var last = sheet.getLastRow();
    if (id !== TEST_ID && last >= 2) {
      var ids = sheet.getRange(2, 1, last - 1, 1).getValues();
      for (var i = 0; i < ids.length; i++) {
        if (String(ids[i][0]) === id) {
          logRaw("kembar", raw);
          return json({ status: "success", duplicate: true });
        }
      }
    }
    sheet.appendRow([id, clip(body.name, 50) || "Anonim", amount, clip(body.message, 300), new Date(), "bagibagi"]);
    logRaw("bagibagi", raw);
    return json({ status: "success" });
  } finally {
    lock.releaseLock();
  }
}

function doGet(e) {
  var p = (e && e.parameter) || {};
  if (!sameKey(p.key, prop("READ_KEY"))) return json({ ok: false, error: "unauthorized" });
  var sheet = getSheet(SHEET_NAME, HEADERS);
  var last = sheet.getLastRow();
  if (p.after === undefined || p.after === "") return json({ ok: true, next: last, items: [] });
  var after = parseInt(p.after, 10);
  if (isNaN(after) || after < 1) after = 1;
  if (after > last) after = last; // sheet dipotong manual → mulai dari baris terakhir yang ada
  var count = Math.min(last - after, MAX_ITEMS);
  var items = [];
  if (count > 0) {
    var rows = sheet.getRange(after + 1, 1, count, 6).getValues();
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i];
      var id = String(r[0] || "");
      if (!id) continue;
      items.push({
        row: after + 1 + i,
        id: id,
        name: String(r[1] || ""),
        amount: toAmount(r[2]),
        message: String(r[3] || ""),
        created: r[4] instanceof Date ? r[4].toISOString() : String(r[4] || ""),
        test: id === TEST_ID,
      });
    }
  }
  return json({ ok: true, next: after + count, items: items });
}
