// Spike S-1/S-2 (Linux only): PDFium via pdfium_dart FFI.
//  S-1 partial: render page, extract text, search.
//  S-2: create REAL PDF annotations (highlight, underline, ink, text note), save a copy,
//       then verify independently (pypdf / poppler) in the calling shell script.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart';

Pointer<UnsignedShort> wide(String s, Arena a) {
  final units = s.codeUnits;
  final p = a.allocate<UnsignedShort>((units.length + 1) * 2);
  for (var i = 0; i < units.length; i++) { p[i] = units[i]; }
  p[units.length] = 0;
  return p;
}

void main(List<String> args) {
  final src = args[0], outPdf = args[1], outPpm = args[2];
  final pdfium = getPdfium();
  pdfium.FPDF_InitLibrary();
  using((arena) {
    final doc = pdfium.FPDF_LoadDocument(src.toNativeUtf8(allocator: arena).cast(), nullptr);
    if (doc == nullptr) throw 'load failed: ${pdfium.FPDF_GetLastError()}';
    print('pages: ${pdfium.FPDF_GetPageCount(doc)}');
    final page = pdfium.FPDF_LoadPage(doc, 0);
    final w = pdfium.FPDF_GetPageWidthF(page), h = pdfium.FPDF_GetPageHeightF(page);
    print('page 0 size: $w x $h pt');

    // --- S-1: render (2x) and make sure it is not blank
    final bw = (w * 2).round(), bh = (h * 2).round();
    final bmp = pdfium.FPDFBitmap_Create(bw, bh, 0);
    pdfium.FPDFBitmap_FillRect(bmp, 0, 0, bw, bh, 0xFFFFFFFF);
    final sw = Stopwatch()..start();
    pdfium.FPDF_RenderPageBitmap(bmp, page, 0, 0, bw, bh, 0, 0x01 /*FPDF_ANNOT*/);
    sw.stop();
    final buf = pdfium.FPDFBitmap_GetBuffer(bmp).cast<Uint8>();
    final stride = pdfium.FPDFBitmap_GetStride(bmp);
    var dark = 0;
    for (var y = 0; y < bh; y += 2) {
      for (var x = 0; x < bw; x += 2) { if (buf[y * stride + x * 4] < 100) dark++; }
    }
    print('render ${bw}x$bh in ${sw.elapsedMilliseconds} ms, dark samples: $dark ${dark > 50 ? "(non-blank)" : "(BLANK!)"}');

    // --- S-1: text extraction + search
    final tp = pdfium.FPDFText_LoadPage(page);
    final n = pdfium.FPDFText_CountChars(tp);
    final tb = arena.allocate<UnsignedShort>((n + 1) * 2);
    pdfium.FPDFText_GetText(tp, 0, n, tb);
    final text = String.fromCharCodes(tb.cast<Uint16>().asTypedList(n));
    print('text chars: $n  contains "resist the pull": ${text.contains("resist the pull")}');
    final sh = pdfium.FPDFText_FindStart(tp, wide('resist the pull', arena), 0, 0);
    final found = pdfium.FPDFText_FindNext(sh);
    final idx = pdfium.FPDFText_GetSchResultIndex(sh), cnt = pdfium.FPDFText_GetSchCount(sh);
    print('search found=$found at char $idx len $cnt');
    // bounding box of the match -> quad points in PDF user space
    var l = 1e9, r = -1e9, b = 1e9, t = -1e9;
    final dl = arena<Double>(), dr = arena<Double>(), db = arena<Double>(), dt = arena<Double>();
    for (var i = idx; i < idx + cnt; i++) {
      pdfium.FPDFText_GetCharBox(tp, i, dl, dr, db, dt);
      if (dl.value < l) l = dl.value; if (dr.value > r) r = dr.value;
      if (db.value < b) b = db.value; if (dt.value > t) t = dt.value;
    }
    print('match bbox: l=$l r=$r b=$b t=$t');
    pdfium.FPDFText_FindClose(sh);

    // --- S-2: create annotations
    void rect(Pointer<FS_RECTF> p, double l, double b, double r, double t) { p.ref.left = l; p.ref.bottom = b; p.ref.right = r; p.ref.top = t; }
    Pointer<FS_QUADPOINTSF> quad(double l, double b, double r, double t) {
      final q = arena<FS_QUADPOINTSF>();
      q.ref.x1 = l; q.ref.y1 = t; q.ref.x2 = r; q.ref.y2 = t; q.ref.x3 = l; q.ref.y3 = b; q.ref.x4 = r; q.ref.y4 = b;
      return q;
    }
    final rc = arena<FS_RECTF>();
    // highlight (subtype 9)
    final hl = pdfium.FPDFPage_CreateAnnot(page, 9);
    rect(rc, l, b, r, t);
    print('hl: setRect=${pdfium.FPDFAnnot_SetRect(hl, rc)} quad=${pdfium.FPDFAnnot_AppendAttachmentPoints(hl, quad(l, b, r, t))} color=${pdfium.FPDFAnnot_SetColor(hl, FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color, 250, 214, 70, 140)}');
    pdfium.FPDFAnnot_SetStringValue(hl, 'Contents'.toNativeUtf8(allocator: arena).cast(), wide('resist the pull', arena));
    pdfium.FPDFPage_CloseAnnot(hl);
    // underline (subtype 10)
    final ul = pdfium.FPDFPage_CreateAnnot(page, 10);
    rect(rc, 72, 650, 300, 670);
    print('ul: setRect=${pdfium.FPDFAnnot_SetRect(ul, rc)} quad=${pdfium.FPDFAnnot_AppendAttachmentPoints(ul, quad(72, 650, 300, 670))} color=${pdfium.FPDFAnnot_SetColor(ul, FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color, 212, 84, 60, 255)}');
    pdfium.FPDFPage_CloseAnnot(ul);
    // ink (subtype 15)
    final ink = pdfium.FPDFPage_CreateAnnot(page, 15);
    rect(rc, 300, 600, 420, 660);
    pdfium.FPDFAnnot_SetRect(ink, rc);
    pdfium.FPDFAnnot_SetColor(ink, FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color, 40, 90, 200, 255);
    final pts = arena<FS_POINTF>(5);
    final xy = [[300, 600], [330, 650], [360, 610], [390, 655], [420, 605]];
    for (var i = 0; i < 5; i++) { pts[i].x = xy[i][0].toDouble(); pts[i].y = xy[i][1].toDouble(); }
    print('ink stroke index: ${pdfium.FPDFAnnot_AddInkStroke(ink, pts, 5)}');
    pdfium.FPDFPage_CloseAnnot(ink);
    // sticky note (subtype 1)
    final note = pdfium.FPDFPage_CreateAnnot(page, 1);
    rect(rc, 500, 700, 520, 720);
    pdfium.FPDFAnnot_SetRect(note, rc);
    pdfium.FPDFAnnot_SetColor(note, FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color, 243, 200, 75, 255);
    print('note contents set: ${pdfium.FPDFAnnot_SetStringValue(note, 'Contents'.toNativeUtf8(allocator: arena).cast(), wide('Compare with Alder ch. 2', arena))}');
    pdfium.FPDFPage_CloseAnnot(note);
    print('annot count on page 0: ${pdfium.FPDFPage_GetAnnotCount(page)}');

    // render again WITH annotations (PDFium's own viewer behaviour)
    pdfium.FPDFBitmap_FillRect(bmp, 0, 0, bw, bh, 0xFFFFFFFF);
    pdfium.FPDF_RenderPageBitmap(bmp, page, 0, 0, bw, bh, 0, 0x01);
    final ppm = BytesBuilder()..add('P6\n$bw $bh\n255\n'.codeUnits);
    for (var y = 0; y < bh; y++) {
      for (var x = 0; x < bw; x++) {
        final o = y * stride + x * 4; ppm.add([buf[o + 2], buf[o + 1], buf[o]]); // BGRA -> RGB
      }
    }
    File(outPpm).writeAsBytesSync(ppm.takeBytes());

    // --- save a COPY (original untouched) through FPDF_FILEWRITE callback
    final out = BytesBuilder();
    final cb = NativeCallable<Int Function(Pointer<FPDF_FILEWRITE_>, Pointer<Void>, UnsignedLong)>.isolateLocal(
      (Pointer<FPDF_FILEWRITE_> self, Pointer<Void> data, int size) { out.add(Uint8List.fromList(data.cast<Uint8>().asTypedList(size))); return 1; },
      exceptionalReturn: 0);
    final fw = arena<FPDF_FILEWRITE_>();
    fw.ref.version = 1;
    fw.ref.WriteBlock = cb.nativeFunction;
    final ok = pdfium.FPDF_SaveAsCopy(doc, fw, 0);
    cb.close();
    File(outPdf).writeAsBytesSync(out.takeBytes());
    print('SaveAsCopy ok=$ok bytes=${File(outPdf).lengthSync()}');

    pdfium.FPDFText_ClosePage(tp);
    pdfium.FPDF_ClosePage(page);
    pdfium.FPDF_CloseDocument(doc);
  });
  pdfium.FPDF_DestroyLibrary();
}
