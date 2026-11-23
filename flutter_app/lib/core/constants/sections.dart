class SectionInfo {
  final String id;
  final String name;
  final String imagePath;
  final String moistureRule;

  const SectionInfo({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.moistureRule,
  });
}

class Sections {
  static const chips = SectionInfo(
    id: 'chips',
    name: 'Chips',
    imagePath: 'assets/images/chips_masala.jpg',
    moistureRule: 'chips',
  );

  static const periPeri = SectionInfo(
    id: 'peri_peri',
    name: 'Peri Peri',
    imagePath: 'assets/images/peri_peri_four_flavours.jpg',
    moistureRule: 'peri_peri',
  );

  static const nimko = SectionInfo(
    id: 'nimko',
    name: 'Nimko',
    imagePath: 'assets/images/daal_moong.jpg',
    moistureRule: 'nimko',
  );

  static const wafer = SectionInfo(
    id: 'wafer',
    name: 'Wafer',
    imagePath: 'assets/images/wafer_trio.jpg',
    moistureRule: 'na',
  );

  static const chocolate = SectionInfo(
    id: 'chocolate',
    name: 'Chocolate',
    imagePath: 'assets/images/chocolate_bar_black.jpg',
    moistureRule: 'na',
  );

  static const all = [chips, periPeri, nimko, wafer, chocolate];

  static SectionInfo byId(String id) {
    return all.firstWhere((s) => s.id == id, orElse: () => chips);
  }

  static List<String> get ids => all.map((s) => s.id).toList();
}

class ShiftHelper {
  static String detectShift() {
    final hour = DateTime.now().hour;
    return (hour >= 8 && hour < 20) ? 'morning' : 'night';
  }

  static String shiftLabel(String shift) {
    return shift == 'morning' ? 'Morning Shift (8AM–8PM)' : 'Night Shift (8PM–8AM)';
  }
}
