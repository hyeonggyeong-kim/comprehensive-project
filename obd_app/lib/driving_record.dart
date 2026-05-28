import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class DrivingRecordScreen extends StatefulWidget {
  const DrivingRecordScreen({super.key});

  @override
  State<DrivingRecordScreen> createState() => _DrivingRecordScreenState();
}

class _DrivingRecordScreenState extends State<DrivingRecordScreen> {
  List<dynamic> _historyList = [];
  bool _isLoading = true;
  final String myIpAddress = '10.20.62.42';

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