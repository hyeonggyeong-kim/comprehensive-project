import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';

class EcoDrivingScreen extends StatefulWidget {
  const EcoDrivingScreen({super.key});

  @override
  State<EcoDrivingScreen> createState() => _EcoDrivingScreenState();
}

class _EcoDrivingScreenState extends State<EcoDrivingScreen> {
  List<dynamic> _ecoHistory = [];
  bool _isLoading = true;
  double _averageEcoScore = 0.0;

  // 💡 본인의 서버 IP로 확인 (기존 화면들과 동일하게 맞추세요)
  final String myIpAddress = '172.30.1.99';

  @override
  void initState() {
    super.initState();
    _fetchEcoData();
  }

  // ================================================================
  // 1. 서버에서 주행 이력(연비 점수 포함)을 가져오는 함수
  // 🟢
  // ================================================================
  Future<void> _fetchEcoData() async {
    final prefs = await SharedPreferences.getInstance();
    final String email = prefs.getString('userEmail') ?? 'test@naver.com';
    final url = Uri.parse('http://$myIpAddress:8080/api/driving/history?email=$email');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));

        // 전체 평균 에코 점수 계산
        double totalScore = 0;
        int validCount = 0;
        for (var record in data) {
          if (record['riskScore'] != null) {
            totalScore += record['riskScore'];
            validCount++;
          }
        }

        setState(() {
          _ecoHistory = data;
          _averageEcoScore = validCount > 0 ? (totalScore / validCount) : 0.0;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("연비 데이터 불러오기 실패: $e");
      setState(() => _isLoading = false);
    }
  }

  // ================================================================
  // 2. 개별 기록 삭제 기능
  // ================================================================
  Future<void> _deleteRecord(int id) async {
    final url = Uri.parse('http://$myIpAddress:8080/api/driving/delete/$id');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        _showSnack('기록이 삭제되었습니다.');
        _fetchEcoData(); // 삭제 후 연비 데이터 새로고침
      }
    } catch (e) {
      debugPrint("삭제 에러: $e");
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
  // 3. 파일 업로드 기능 (CSV, JSON, XLSX)
  // ================================================================
  Future<void> _uploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json', 'xlsx'],
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final fileName = result.files.single.name.toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final String email = prefs.getString('userEmail') ?? 'test@naver.com';

    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> detailedRows = [];
      String startTime = '';
      String endTime = '';
      double avgSpeed = 0;
      double avgRpm = 0;

      if (fileName.endsWith('.csv')) {
        final lines = await file.readAsLines();
        if (lines.length < 2) {
          setState(() => _isLoading = false);
          return _showSnack('데이터가 없는 파일입니다.');
        }
        final headers = lines[0].split(',').map((h) => h.trim()).toList();
        for (int i = 1; i < lines.length; i++) {
          final vals = lines[i].split(',');
          if (vals.length < headers.length) continue;
          final row = <String, dynamic>{};
          for (int j = 0; j < headers.length; j++) row[headers[j]] = vals[j].trim();
          detailedRows.add(_normalizeCsvRow(row, i - 1));
        }
      } else if (fileName.endsWith('.xlsx')) {
        final bytes = await file.readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        final sheet = excel.tables[excel.tables.keys.first];
        if (sheet == null || sheet.rows.length < 2) {
          setState(() => _isLoading = false);
          return _showSnack('데이터가 없는 파일입니다.');
        }
        final headers = sheet.rows[0].map((cell) => cell?.value?.toString().trim() ?? '').toList();
        for (int i = 1; i < sheet.rows.length; i++) {
          final row = <String, dynamic>{};
          for (int j = 0; j < headers.length; j++) {
            if (j < sheet.rows[i].length) row[headers[j]] = sheet.rows[i][j]?.value?.toString() ?? '0';
          }
          detailedRows.add(_normalizeCsvRow(row, i - 1));
        }
      } else {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          for (int i = 0; i < decoded.length; i++) detailedRows.add(_normalizeJsonRow(decoded[i], i));
        } else if (decoded is Map) {
          final list = decoded['records'] ?? decoded['data'] ?? [];
          for (int i = 0; i < list.length; i++) detailedRows.add(_normalizeJsonRow(list[i], i));
        }
      }

      if (detailedRows.isEmpty) {
        setState(() => _isLoading = false);
        return _showSnack('파싱된 데이터가 없습니다. 파일 형식을 확인하세요.');
      }

      avgSpeed = detailedRows.map((r) => _toDouble(r['speed'])).reduce((a, b) => a + b) / detailedRows.length;
      avgRpm = detailedRows.map((r) => _toDouble(r['rpm'])).reduce((a, b) => a + b) / detailedRows.length;

      final now = DateTime.now();
      startTime = '${now.year}-${_pad(now.month)}-${_pad(now.day)} ${_pad(now.hour)}:${_pad(now.minute)}';
      endTime = startTime;

      final payload = {
        'userEmail': email,
        'startTime': startTime,
        'endTime': endTime,
        'avgSpeed': avgSpeed,
        'avgRpm': avgRpm,
        'detailedData': jsonEncode(detailedRows),
      };

      _showSnack('파일 분석 중... 서버로 전송합니다.');

      final url = Uri.parse('http://$myIpAddress:8080/api/driving/save');
      final response = await http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        final score = res['risk_score'] ?? 0.0;
        final label = res['risk_label'] ?? '';
        _showSnack('업로드 완료! 점수: ${score.toStringAsFixed(1)}점 ($label)');
        _fetchEcoData(); // 업로드 성공 시 연비 데이터 다시 불러오기
      } else {
        setState(() => _isLoading = false);
        _showSnack('서버 오류: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('파일 업로드 오류: $e');
      setState(() => _isLoading = false);
      _showSnack('오류가 발생했습니다: $e');
    }
  }

  // ================================================================
  // 4. 유틸리티 헬퍼 함수
  // ================================================================
  Map<String, dynamic> _normalizeCsvRow(Map<String, dynamic> row, int index) {
    return {
      'timestamp': index,
      'speed': _toDouble(row['차량 속도 센서'] ?? row['speed'] ?? row['SPEED']),
      'rpm': _toDouble(row['엔진 회전수'] ?? row['rpm'] ?? row['ENGINE_RPM']),
      'throttle': _toDouble(row['스로틀 위치 절대값'] ?? row['throttle'] ?? row['THROTTLE_POS']),
      'load': _toDouble(row['엔진 부하'] ?? row['load'] ?? row['ENGINE_LOAD']),
      'coolant': _toDouble(row['엔진 냉각 온도'] ?? row['coolant'] ?? row['ENGINE_COOLANT_TEMP']),
      'iat': _toDouble(row['흡입 공기 온도 (IAT)'] ?? row['iat'] ?? row['AIR_INTAKE_TEMP']),
      'maf': _toDouble(row['공기량 (MAF) 센서'] ?? row['maf'] ?? row['MAF']),
      'lat': _toDouble(row['Lat.'] ?? row['lat'] ?? 0),
      'lon': _toDouble(row['Lon.'] ?? row['lon'] ?? 0),
    };
  }

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Color _getScoreColor(double score) {
    if (score >= 66) return Colors.green;
    if (score >= 33) return Colors.orange;
    return Colors.red;
  }

  // ================================================================
  // 5. 화면 그리기 (UI 빌드)
  // ================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: const Text('내 연비/에코 분석', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 1,
        actions: [
          // 💡 여기에 업로드 버튼 추가됨!
          IconButton(
            icon: const Icon(Icons.upload_file, color: Colors.blue),
            tooltip: '파일 업로드',
            onPressed: _uploadFile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)
              ],
            ),
            child: Column(
              children: [
                const Text('나의 종합 에코 운전 점수', style: TextStyle(fontSize: 16, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(
                  '${_averageEcoScore.toStringAsFixed(1)}점',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: _getScoreColor(_averageEcoScore),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _averageEcoScore >= 66 ? '훌륭한 연비 주행 습관을 가지고 계시네요!' : '급가속을 줄이면 연비가 더 좋아집니다.',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('최근 주행 연비 리스트', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),

          Expanded(
            child: _ecoHistory.isEmpty
                ? const Center(child: Text('주행 기록이 없습니다.\n우측 상단의 업로드 버튼을 눌러보세요!'))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _ecoHistory.length,
              itemBuilder: (context, index) {
                var record = _ecoHistory[index];
                double score = record['riskScore'] ?? 0.0;
                String label = record['riskLabel'] ?? '측정 불가';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getScoreColor(score).withOpacity(0.2),
                      child: Icon(Icons.eco, color: _getScoreColor(score)),
                    ),
                    title: Text(record['startTime']?.toString() ?? '날짜 없음', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text('평균 속도: ${record['avgSpeed']} km/h'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min, // 우측에 아이콘들 배치하기 위함
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${score.toStringAsFixed(1)}점', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _getScoreColor(score))),
                            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        // 💡 여기에 삭제(휴지통) 버튼 추가됨!
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _confirmDelete(record['id']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}