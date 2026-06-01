import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';

class DrivingRecordScreen extends StatefulWidget {
  const DrivingRecordScreen({super.key});

  @override
  State<DrivingRecordScreen> createState() => _DrivingRecordScreenState();
}

class _DrivingRecordScreenState extends State<DrivingRecordScreen> {
  List<dynamic> _historyList = [];
  bool _isLoading = true;
  final String myIpAddress = '172.16.38.86';

  @override
  void initState() {
    super.initState();
    _fetchDrivingHistory();
  }

  Future<void> _fetchDrivingHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String email = prefs.getString('userEmail') ?? 'test@naver.com';
    final url = Uri.parse('http://$myIpAddress:8080/api/driving/history?email=$email');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _historyList = jsonDecode(utf8.decode(response.bodyBytes));
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("기록 불러오기 실패: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRecord(int id) async {
    final url = Uri.parse('http://$myIpAddress:8080/api/driving/delete/$id');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('기록이 삭제되었습니다.')));
        _fetchDrivingHistory();
      }
    } catch (e) {
      debugPrint("삭제 에러: $e");
    }
  }

  // ================================================================
  // 파일 업로드 (CSV / JSON) → 파싱 → 백엔드 전송 + AI 분석
  // 🟢
  // ================================================================
  Future<void> _uploadFile() async {
    // 1. 파일 선택 (CSV, JSON, XLS, XLSX 모두 허용)
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json', 'xls', 'xlsx'],
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final fileName = result.files.single.name.toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final String email = prefs.getString('userEmail') ?? 'test@naver.com';

    try {
      List<Map<String, dynamic>> detailedRows = [];
      String startTime = '';
      String endTime = '';
      double avgSpeed = 0;
      double avgRpm = 0;

      if (fileName.endsWith('.csv')) {
        // ── CSV 파싱 ────────────────────────────────────────────────
        final lines = await file.readAsLines();
        if (lines.length < 2) {
          _showSnack('데이터가 없는 파일입니다.');
          return;
        }
        final headers = lines[0].split(',').map((h) => h.trim()).toList();

        for (int i = 1; i < lines.length; i++) {
          final vals = lines[i].split(',');
          if (vals.length < headers.length) continue;
          final row = <String, dynamic>{};
          for (int j = 0; j < headers.length; j++) {
            row[headers[j]] = vals[j].trim();
          }
          detailedRows.add(_normalizeCsvRow(row, i - 1));
        }
      } else if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
        // ── XLS / XLSX 파싱 ─────────────────────────────────────────
        final bytes = await file.readAsBytes();
        final excel = Excel.decodeBytes(bytes);

        // 첫 번째 시트 사용
        final sheet = excel.tables[excel.tables.keys.first];
        if (sheet == null || sheet.rows.length < 2) {
          _showSnack('데이터가 없는 파일입니다.');
          return;
        }

        // 첫 행 = 헤더
        final headers = sheet.rows[0]
            .map((cell) => cell?.value?.toString().trim() ?? '')
            .toList();

        for (int i = 1; i < sheet.rows.length; i++) {
          final row = <String, dynamic>{};
          for (int j = 0; j < headers.length; j++) {
            if (j < sheet.rows[i].length) {
              row[headers[j]] = sheet.rows[i][j]?.value?.toString() ?? '0';
            }
          }
          detailedRows.add(_normalizeCsvRow(row, i - 1)); // CSV와 동일한 정규화
        }
      } else {
        // ── JSON 파싱 ────────────────────────────────────────────────
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          for (int i = 0; i < decoded.length; i++) {
            detailedRows.add(_normalizeJsonRow(decoded[i], i));
          }
        } else if (decoded is Map) {
          // { "records": [...] } 형태도 허용
          final list = decoded['records'] ?? decoded['data'] ?? [];
          for (int i = 0; i < list.length; i++) {
            detailedRows.add(_normalizeJsonRow(list[i], i));
          }
        }
      }

      if (detailedRows.isEmpty) {
        _showSnack('파싱된 데이터가 없습니다. 파일 형식을 확인하세요.');
        return;
      }

      // 2. 평균 계산
      avgSpeed = detailedRows
          .map((r) => _toDouble(r['speed']))
          .reduce((a, b) => a + b) /
          detailedRows.length;
      avgRpm = detailedRows
          .map((r) => _toDouble(r['rpm']))
          .reduce((a, b) => a + b) /
          detailedRows.length;

      // 3. 시작/종료 시간 (파일명 또는 현재 시각 기반)
      final now = DateTime.now();
      startTime =
      '${now.year}-${_pad(now.month)}-${_pad(now.day)} ${_pad(now.hour)}:${_pad(now.minute)}';
      endTime = startTime;

      // 4. 백엔드로 전송
      final payload = {
        'userEmail': email,
        'startTime': startTime,
        'endTime': endTime,
        'avgSpeed': avgSpeed,
        'avgRpm': avgRpm,
        'detailedData': jsonEncode(detailedRows),
      };

      _showSnack('파일 분석 중... (AI 위험도 계산 포함)');

      final url =
      Uri.parse('http://$myIpAddress:8080/api/driving/save');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        final score = res['risk_score'] ?? 0.0;
        final label = res['risk_label'] ?? '';
        _showSnack(
            '업로드 완료! AI 위험도: ${score.toStringAsFixed(1)}점 ($label)');
        _fetchDrivingHistory(); // 목록 갱신
      } else {
        _showSnack('서버 오류: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('파일 업로드 오류: $e');
      _showSnack('오류가 발생했습니다: $e');
    }
  }

  /// CSV 행을 백엔드가 기대하는 키 형식으로 정규화
  Map<String, dynamic> _normalizeCsvRow(
      Map<String, dynamic> row, int index) {
    return {
      'timestamp': index,
      'speed': _toDouble(row['차량 속도 센서'] ?? row['speed'] ?? row['SPEED']),
      'rpm': _toDouble(row['엔진 회전수'] ?? row['rpm'] ?? row['ENGINE_RPM']),
      'throttle':
      _toDouble(row['스로틀 위치 절대값'] ?? row['throttle'] ?? row['THROTTLE_POS']),
      'load': _toDouble(row['엔진 부하'] ?? row['load'] ?? row['ENGINE_LOAD']),
      'coolant': _toDouble(
          row['엔진 냉각 온도'] ?? row['coolant'] ?? row['ENGINE_COOLANT_TEMP']),
      'iat': _toDouble(
          row['흡입 공기 온도 (IAT)'] ?? row['iat'] ?? row['AIR_INTAKE_TEMP']),
      'maf': _toDouble(row['공기량 (MAF) 센서'] ?? row['maf'] ?? row['MAF']),
      'lat': _toDouble(row['Lat.'] ?? row['lat'] ?? 0),
      'lon': _toDouble(row['Lon.'] ?? row['lon'] ?? 0),
    };
  }

  /// JSON 행 정규화
  Map<String, dynamic> _normalizeJsonRow(dynamic row, int index) {
    if (row is! Map) return {'timestamp': index};
    return {
      'timestamp': row['timestamp'] ?? index,
      'speed': _toDouble(row['speed'] ?? row['SPEED']),
      'rpm': _toDouble(row['rpm'] ?? row['ENGINE_RPM']),
      'throttle': _toDouble(row['throttle'] ?? row['THROTTLE_POS']),
      'load': _toDouble(row['load'] ?? row['ENGINE_LOAD']),
      'coolant': _toDouble(row['coolant'] ?? row['ENGINE_COOLANT_TEMP']),
      'iat': _toDouble(row['iat'] ?? row['AIR_INTAKE_TEMP']),
      'maf': _toDouble(row['maf'] ?? row['MAF']),
      'lat': _toDouble(row['lat'] ?? 0),
      'lon': _toDouble(row['lon'] ?? 0),
    };
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _exportToExcel(Map<String, dynamic> record) async {
    try {
      List<dynamic> details = jsonDecode(record['detailedData']);
      if (details.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('상세 주행 데이터가 없습니다.')));
        return;
      }

      DateTime startDt;
      try {
        String st = record['startTime'];
        startDt = DateTime.parse(st.length == 16 ? "$st:00" : st);
      } catch (e) {
        startDt = DateTime.now();
      }

      String csvData =
          "시간,Lat.,Lon.,차량 속도 센서,엔진 회전수,액셀러레이터 페달 위치 D,스로틀 위치 절대값,"
          "연료 레일 압력,공기량 (MAF) 센서,연료 잔여량,엔진 기준 토크,엔진 부하,"
          "흡기 매니폴드 절대 압력 (MAP),엔진 오일 온도,엔진 냉각 온도,"
          "연료 단기 보정 (뱅크1),연료 단기 보정 (뱅크2),연료 장기 보정 (뱅크1),"
          "연료 장기 보정 (뱅크2),외부 공기 온도,대기압 압력,"
          "하이브리드/EV 배터리 팩 잔여 충전량,미립자 필터 (PF) 델타 압력 (뱅크1),"
          "미립자 필터 (PF) 입구 온도 (뱅크1),흡입 공기 온도 (IAT),"
          "배기 가스 온도 (뱅크1 센서1),배기 가스 온도 (뱅크2 센서1),제어 모듈 전압\n";

      for (var d in details) {
        int secondsElapsed = d['timestamp'];
        DateTime currentDt = startDt.add(Duration(seconds: secondsElapsed));
        String h = currentDt.hour.toString().padLeft(2, '0');
        String m = currentDt.minute.toString().padLeft(2, '0');
        String s = currentDt.second.toString().padLeft(2, '0');
        String realTime = "$h:$m:$s";

        String lat      = d['lat']?.toString()            ?? "0";
        String lon      = d['lon']?.toString()            ?? "0";
        String speed    = d['speed']?.toString()          ?? "0";
        String rpm      = d['rpm']?.toString()            ?? "0";
        String pedalD   = d['pedal_d']?.toString()        ?? "0";
        String throttle = d['throttle']?.toString()       ?? "0";
        String fuelRail = d['fuel_rail']?.toString()      ?? "0";
        String maf      = d['maf']?.toString()            ?? "0";
        String fuelLevel= d['fuel_level']?.toString()     ?? "0";
        String torque   = d['torque']?.toString()         ?? "0";
        String load     = d['load']?.toString()           ?? "0";
        String mapV     = d['map']?.toString()            ?? "0";
        String oilTemp  = d['oil_temp']?.toString()       ?? "0";
        String coolant  = d['coolant']?.toString()        ?? "0";
        String stft1    = d['stft1']?.toString()          ?? "0";
        String stft2    = d['stft2']?.toString()          ?? "0";
        String ltft1    = d['ltft1']?.toString()          ?? "0";
        String ltft2    = d['ltft2']?.toString()          ?? "0";
        String ambient  = d['ambient_temp']?.toString()   ?? "0";
        String baro     = d['barometric']?.toString()     ?? "0";
        String evBatt   = d['ev_battery']?.toString()     ?? "0";
        String dpfDelta = d['dpf_delta']?.toString()      ?? "0";
        String dpfTemp  = d['dpf_temp']?.toString()       ?? "0";
        String iat      = d['iat']?.toString()            ?? "0";
        String egt1     = d['egt1']?.toString()           ?? "0";
        String egt2     = d['egt2']?.toString()           ?? "0";
        String voltage  = d['module_voltage']?.toString() ?? "0";

        csvData +=
        "$realTime,$lat,$lon,$speed,$rpm,$pedalD,$throttle,$fuelRail,"
            "$maf,$fuelLevel,$torque,$load,$mapV,$oilTemp,$coolant,"
            "$stft1,$stft2,$ltft1,$ltft2,$ambient,$baro,$evBatt,"
            "$dpfDelta,$dpfTemp,$iat,$egt1,$egt2,$voltage\n";
      }

      final directory = await getTemporaryDirectory();
      String safeName = record['startTime'].replaceAll(':', '-');
      final file = File('${directory.path}/운전기록_$safeName.csv');

      List<int> bytes = [0xEF, 0xBB, 0xBF];
      bytes.addAll(utf8.encode(csvData));
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/octet-stream')],
      );
    } catch (e) {
      debugPrint("엑셀 변환 에러: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파일 생성 중 오류가 발생했습니다.')));
    }
  }

  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록 삭제'),
        content: const Text('이 주행 기록을 영구적으로 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteRecord(id);
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // build
  // ================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: const Text('내 주행 기록',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file, color: Colors.blue),
            tooltip: 'CSV / JSON / XLSX 파일 업로드',
            onPressed: _uploadFile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historyList.isEmpty
          ? const Center(
        child: Text(
          '저장된 주행 기록이 없습니다.\n대시보드에서 주행을 시작해보세요!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.blueGrey),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _historyList.length,
        itemBuilder: (context, index) {
          var record = _historyList[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 날짜 + 버튼 행
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_month,
                              color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            "${record['startTime']} ~",
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.download_rounded,
                                color: Colors.green),
                            onPressed: () => _exportToExcel(record),
                            tooltip: '엑셀 데이터 다운로드',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () =>
                                _confirmDelete(record['id']),
                            tooltip: '기록 삭제',
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 10, thickness: 1),
                  const SizedBox(height: 10),
                  // 통계 3개 행
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(Icons.speed, "평균 속도",
                          "${record['avgSpeed']} km/h", Colors.orange),
                      _buildStatItem(Icons.settings, "평균 RPM",
                          "${record['avgRpm']} RPM", Colors.purple),
                      _buildRiskItem(record['riskScore']),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ================================================================
  // 위젯 헬퍼 — 클래스 레벨 메서드 (서로 완전히 분리)
  // ================================================================

  /// 속도 / RPM 통계 카드
  Widget _buildStatItem(
      IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// AI 위험도 카드
  Widget _buildRiskItem(dynamic rawScore) {
    double score = 0.0;
    try {
      score = double.parse(rawScore.toString());
    } catch (_) {}

    final Color color;
    final String label;
    final IconData icon;

    if (score < 33) {
      color = Colors.green;
      label = "안전";
      icon = Icons.sentiment_satisfied_alt;
    } else if (score < 66) {
      color = Colors.orange;
      label = "보통";
      icon = Icons.sentiment_neutral;
    } else {
      color = Colors.red;
      label = "위험";
      icon = Icons.sentiment_very_dissatisfied;
    }

    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        const Text("AI 위험도",
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          "${score.toStringAsFixed(1)}점 ($label)",
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}