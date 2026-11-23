import 'package:flutter/material.dart';
import '../../../../models/temp_humidity_model.dart';

class THRowController {
  final TextEditingController time = TextEditingController();
  final TextEditingController temperature = TextEditingController();
  final TextEditingController humidity = TextEditingController();
  final TextEditingController remarks = TextEditingController();

  THRowController();

  THRowController.fromRow(TempHumidityRow row) {
    time.text = row.time;
    temperature.text = row.temperature?.toString() ?? '';
    humidity.text = row.humidity?.toString() ?? '';
    remarks.text = row.remarks;
  }

  TempHumidityRow toRow(String sectionName, String qcName) => TempHumidityRow(
    time: time.text.trim(),
    temperature: double.tryParse(temperature.text),
    humidity: double.tryParse(humidity.text),
    section: sectionName,
    verifiedByQc: qcName,
    remarks: remarks.text.trim(),
  );

  void dispose() {
    time.dispose();
    temperature.dispose();
    humidity.dispose();
    remarks.dispose();
  }
}