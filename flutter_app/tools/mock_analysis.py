"""
Accurate preview of the REAL analysis sheets the app now produces.

Sheet 1  'PeriPeriWk'  = per-SECTION weekly comparison (one sheet PER section:
   ChipsWk, PeriPeriWk, NimkoWk, WaferWk, ChocolateWk). For that section it
   compares each metric (Weight, Leakage, Printing, Moisture) week-over-week:
   a Green/Yellow/Red % table by week + a Yellow/Red column chart.
   (report_service.dart _xSectionWeeklySheet + _xWeeklyMetricBlock)

Sheet 2  'BySection'   = each metric across ALL sections in one place.
   (report_service.dart _xBySectionSheet)

Visual mock with fake numbers; the app builds the same layout live from data.
"""
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.chart import BarChart, Reference

NAVY, LIGHTB = "0D47A1", "E3F2FD"
GREEN_F, GREEN_T = "C8E6C9", "1E7145"
YELL_F,  YELL_T  = "FFF59D", "9C6500"
RED_F,   RED_T   = "EF9A9A", "9C0006"
BLOCK_TITLE = "0D47A1"
thin = Side(style="thin", color="BFBFBF")
BORDER = Border(left=thin, right=thin, top=thin, bottom=thin)

def fill(h): return PatternFill("solid", fgColor=h)
def bold(sz=11, c="000000"): return Font(bold=True, size=sz, color=c)

def sheet_header(ws, title, ncols, note):
    last = chr(64 + ncols)
    ws.merge_cells(f"A1:{last}1")
    c = ws["A1"]; c.value = f"REMOXIN ENTERPRISES — {title}"
    c.font = bold(13, "FFFFFF"); c.fill = fill(NAVY); c.alignment = Alignment(horizontal="center")
    ws.merge_cells(f"A2:{last}2")
    c = ws["A2"]; c.value = f"Period: 12 May – 06 Jul 2026   ·   {note}"
    c.font = bold(); c.fill = fill(LIGHTB)

def qcell(cell, pct, kind):
    cell.value = pct; cell.number_format = "0.00"
    cell.alignment = Alignment(horizontal="center"); cell.border = BORDER
    f, t = {"g": (GREEN_F, GREEN_T), "y": (YELL_F, YELL_T), "r": (RED_F, RED_T)}[kind]
    cell.fill = fill(f); cell.font = Font(color=t, bold=True)

def autofit(ws, cols):
    for col in cols:
        w = max((len(str(c.value)) for c in ws[col] if c.value), default=10)
        ws.column_dimensions[col].width = min(w + 3, 34)

wb = Workbook()

# ══ SHEET 1: WeeklyBySection — all sections stacked, one scrollable sheet ═════
ws = wb.active
ws.title = "WeeklyBySection"
sheet_header(ws, "WEEKLY BY SECTION — Weak Link", 14,
             "Scroll down for each section. Every metric compared week-over-week. Yellow = warn, Red = fail.")

WEEKS = ["Wk 5 (12–18 May)", "Wk 6 (19–25 May)", "Wk 7 (26 May–01 Jun)", "Wk 8 (02–08 Jun)"]
METRICS = ["Weight Variation", "Leakage", "Printing", "Moisture"]
# section -> metric -> per-week (green%, yellow%, red%, entries)
import random
random.seed(7)
def wk_series(base_red):
    out = []
    for _ in WEEKS:
        rd = max(0, base_red + random.randint(-1, 2))
        y = random.randint(1, 8)
        g = 100 - y - rd
        out.append((g, y, rd, random.randint(45, 70)))
    return out
SEED = {"Weight Variation": 2, "Leakage": 2, "Printing": 1, "Moisture": 3}
SECTIONS_WK = {s: {m: wk_series(SEED[m]) for m in METRICS}
               for s in ["Chips", "Peri Peri", "Nimko", "Wafer", "Chocolate"]}

row = 4
for sec, metricmap in SECTIONS_WK.items():
    ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=14)
    b = ws.cell(row, 1, f"◆  {sec.upper()}")
    b.font = bold(12, "FFFFFF"); b.fill = fill("37474F")
    row += 1
    for metric in METRICS:
        weekvals = metricmap[metric]
        ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=5)
        t = ws.cell(row, 1, f"{metric} — weekly defect %")
        t.font = bold(11, "FFFFFF"); t.fill = fill(BLOCK_TITLE)
        hdr = row + 1
        for i, h in enumerate(["Week", "Green %", "Yellow %", "Red %", "Entries"]):
            cc = ws.cell(hdr, i + 1, h); cc.font = bold(); cc.border = BORDER
            cc.alignment = Alignment(horizontal="center")
        ws.cell(hdr, 2).fill = fill(GREEN_F); ws.cell(hdr, 3).fill = fill(YELL_F); ws.cell(hdr, 4).fill = fill(RED_F)
        r = hdr + 1; first = r
        for wk, (g, y, rd, n) in zip(WEEKS, weekvals):
            ws.cell(r, 1, wk).border = BORDER
            qcell(ws.cell(r, 2), g, "g"); qcell(ws.cell(r, 3), y, "y"); qcell(ws.cell(r, 4), rd, "r")
            e = ws.cell(r, 5, n); e.alignment = Alignment(horizontal="center"); e.border = BORDER
            r += 1
        last = r - 1
        ch = BarChart(); ch.type = "col"; ch.title = f"{metric} (Yellow=warn, Red=fail)"
        ch.height = 6.5; ch.width = 15
        data = Reference(ws, min_col=3, max_col=4, min_row=hdr, max_row=last)
        cats = Reference(ws, min_col=1, max_col=1, min_row=first, max_row=last)
        ch.add_data(data, titles_from_data=True); ch.set_categories(cats)
        ws.add_chart(ch, f"G{row}")
        row = max(last, row + 15) + 2
    row += 1
autofit(ws, "ABCDE")

# ══ SHEET 2: BySection — each metric across all sections ═════════════════════
ws2 = wb.create_sheet("BySection")
sheet_header(ws2, "BY SECTION — Weak Link", 15,
             "Each metric across all sections. Weak Link = machine with the most defects.")
SECTIONS = ["Chips", "Peri Peri", "Nimko", "Wafer", "Chocolate"]
BY = {
    "Weight Variation": {"Chips": (96,3,1,498,"M-5 (7 def)"), "Peri Peri": (89,7,4,237,"M-12 (26 def)"),
        "Nimko": (94,4,2,356,"M-3 (21 def)"), "Wafer": (99,1,0,149,"M-2 (1 def)"), "Chocolate": (91,6,3,128,"M-8 (11 def)")},
    "Leakage": {"Chips": (93,5,2,498,"M-7 (35 def)"), "Peri Peri": (91,6,3,237,"M-12 (22 def)"),
        "Nimko": (97,2,1,356,"M-3 (11 def)"), "Wafer": (95,4,1,149,"M-2 (7 def)"), "Chocolate": (85,9,6,128,"M-8 (19 def)")},
    "Printing": {"Chips": (98,1,1,498,"M-10 (10 def)"), "Peri Peri": (97,2,1,237,"M-6 (11 def)"),
        "Nimko": (99,1,0,356,"M-11 (4 def)"), "Wafer": (97,2,1,149,"M-2 (5 def)"), "Chocolate": (96,3,1,128,"M-8 (5 def)")},
    "Moisture": {"Chips": (92,6,2,498,"M-5 (40 def)"), "Peri Peri": (88,9,3,237,"M-12 (24 def)"),
        "Nimko": (90,7,3,356,"M-3 (36 def)"), "Wafer": (0,0,0,0,"—"), "Chocolate": (0,0,0,0,"—")},
}
row = 4
for metric, secmap in BY.items():
    ws2.merge_cells(start_row=row, start_column=1, end_row=row, end_column=6)
    t = ws2.cell(row, 1, f"{metric} — by section")
    t.font = bold(11, "FFFFFF"); t.fill = fill(BLOCK_TITLE)
    hdr = row + 1
    for i, h in enumerate(["Section", "Green %", "Yellow %", "Red %", "Entries", "Weak Link (machine)"]):
        cc = ws2.cell(hdr, i + 1, h); cc.font = bold(); cc.border = BORDER
        cc.alignment = Alignment(horizontal="center")
    ws2.cell(hdr, 2).fill = fill(GREEN_F); ws2.cell(hdr, 3).fill = fill(YELL_F); ws2.cell(hdr, 4).fill = fill(RED_F)
    r = hdr + 1; first = r
    for s in SECTIONS:
        g, y, rd, n, weak = secmap[s]
        ws2.cell(r, 1, s).font = bold(); ws2.cell(r, 1).border = BORDER
        qcell(ws2.cell(r, 2), g, "g"); qcell(ws2.cell(r, 3), y, "y"); qcell(ws2.cell(r, 4), rd, "r")
        e = ws2.cell(r, 5, n); e.alignment = Alignment(horizontal="center"); e.border = BORDER
        wl = ws2.cell(r, 6, weak); wl.border = BORDER
        wl.font = Font(color=RED_T if weak != "—" else "808080")
        r += 1
    last = r - 1
    ch = BarChart(); ch.type = "col"; ch.title = f"{metric} by section (Yellow/Red)"
    ch.height = 6.5; ch.width = 14
    data = Reference(ws2, min_col=3, max_col=4, min_row=hdr, max_row=last)
    cats = Reference(ws2, min_col=1, max_col=1, min_row=first, max_row=last)
    ch.add_data(data, titles_from_data=True); ch.set_categories(cats)
    ws2.add_chart(ch, f"H{row}")
    row = max(last, row + 12) + 2
autofit(ws2, "ABCDEF")

out = r"C:\Users\dell\Desktop\SAMPLE_Analysis_Mockup.xlsx"
wb.save(out)
print("Saved:", out)
