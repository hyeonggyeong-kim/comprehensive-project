import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DiagnosticScreen extends StatefulWidget {
  final BluetoothDevice? device;
  const DiagnosticScreen({super.key, this.device});

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  bool _isScanning = false;

  // 💡 이제 코드 번호만 저장하는 게 아니라, 서버에서 받아온 뜻(description)도 같이 저장합니다.
  List<Map<String, String>> _foundDTCs = [];

  // 💡 본인의 서버 IP (핫스팟 환경 등 상황에 맞게 수정하세요)
  final String myIpAddress = '192.168.0.22';

  // ================================================================
  // 1. 진단(조회) 시작 함수
  // ================================================================
  Future<void> _startDiagnosis() async {
    setState(() {
      _isScanning = true;
      _foundDTCs.clear();
    });

    if (widget.device != null) {
      await _readRealDTC();
    } else {
      // 💡 시뮬레이션: 블루투스 기기가 없을 때 테스트용으로 P0113과 P0420을 서버에 물어봅니다.
      await Future.delayed(const Duration(seconds: 3));
      await _fetchDtcMeaning('P0113');
      await _fetchDtcMeaning('P0420');
    }

    setState(() => _isScanning = false);

    // 진단 결과 DB 저장
    await _saveResultToDB();
  }

  // ================================================================
  // 2. 서버에 고장 코드 뜻 물어보기 (NEW!)
  // ================================================================
  Future<void> _fetchDtcMeaning(String code) async {
    final url = Uri.parse('http://$myIpAddress:8080/api/diagnostics/code/$code');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        // 서버가 "code: P0113, description: 흡기 온도 센서 이상" 이라고 대답해줍니다.
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _foundDTCs.add({
            'code': data['code'] ?? code,
            'description': data['description'] ?? '알 수 없는 코드입니다.'
          });
        });
      } else {
        setState(() => _foundDTCs.add({'code': code, 'description': '서버 응답 오류'}));
      }
    } catch (e) {
      debugPrint("사전 조회 실패: $e");
      setState(() => _foundDTCs.add({'code': code, 'description': '네트워크 오류'}));
    }
  }

  // ================================================================
  // 3. 진단 결과 DB 저장
  // ================================================================
  // ================================================================
  // 3. 진단 결과 DB 저장
  // ================================================================
  Future<void> _saveResultToDB() async {
    final prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString('userEmail');
    if (email == null) return;

    final String myIpAddress = '192.168.0.22'; // 핫스팟 IP 적용
    final url = Uri.parse('http://$myIpAddress:8080/api/diagnostics/save');

    // 👇 여기부터 👇 (이 부분이 병합 중에 빠졌습니다!)
    // 🟢
    String codeString = _foundDTCs.isEmpty
        ? '정상'
        : _foundDTCs.map((item) => item['code']).join(',');
    // 👆 여기까지 추가 👆

    try {
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userEmail': email,
          'dtcCodes': codeString,  // 이제 여기서 에러가 나지 않습니다!
          'statusMessage': _foundDTCs.isEmpty ? '차량 상태 정상' : '고장 코드 ${_foundDTCs.length}건 발견'
        }),
      );
    } catch (e) {
      debugPrint("저장 실패: $e");
    }
  }

  // ================================================================
  // 4. 이력 조회 팝업
  // ================================================================
  void _showHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString('userEmail');
    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }

    final url = Uri.parse('http://$myIpAddress:8080/api/diagnostics/history?email=$email');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('과거 진단 이력'),
        content: SizedBox(
          width: double.maxFinite, height: 300,
          child: FutureBuilder(
            future: http.get(url),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (!snapshot.hasData) return const Center(child: Text('기록이 없습니다.'));
              List history = jsonDecode(utf8.decode(snapshot.data!.bodyBytes));
              return ListView.builder(
                itemCount: history.length,
                itemBuilder: (context, index) {
                  var item = history[index];
                  return ListTile(
                    leading: Icon(Icons.history, color: item['dtcCodes'] == '정상' ? Colors.green : Colors.red),
                    title: Text(item['statusMessage']),
                    subtitle: Text('날짜: ${item['scanDate'].toString().substring(0, 10)}'),
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
      ),
    );
  }

  // ================================================================
  // 5. 실제 블루투스 DTC 조회 로직
  // ================================================================
  Future<void> _readRealDTC() async {
    try {
      List<BluetoothService> services = await widget.device!.discoverServices();
      BluetoothCharacteristic? writeChar; BluetoothCharacteristic? notifyChar;
      for (var s in services) {
        for (var c in s.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) writeChar = c;
          if (c.properties.notify || c.properties.indicate) notifyChar = c;
        }
      }
      if (notifyChar != null && writeChar != null) {
        await notifyChar.setNotifyValue(true);
        StreamSubscription sub = notifyChar.lastValueStream.listen((value) async {
          String response = utf8.decode(value, allowMalformed: true).replaceAll(RegExp(r'[\s\r\n>]'), '');
          if (response.startsWith("43") && response.length >= 6) {
            String hexCode = response.substring(2, 6);
            if (hexCode != "0000") {
              String parsedCode = _parseOBDDTC(hexCode);

              // 💡 이미 조회한 코드가 아니라면 서버에 물어봅니다!
              bool alreadyExists = _foundDTCs.any((item) => item['code'] == parsedCode);
              if (!alreadyExists) {
                await _fetchDtcMeaning(parsedCode);
              }
            }
          }
        });

        await writeChar.write(utf8.encode("03\r"));
        await Future.delayed(const Duration(seconds: 4));
        await sub.cancel();
      }
    } catch (e) {
      debugPrint("진단 에러: $e");
    }
  }

  String _parseOBDDTC(String hexStr) {
    if (hexStr.length < 4) return "Unknown";
    int firstChar = int.parse(hexStr[0], radix: 16);
    String dtcLetter = ["P", "P", "P", "P", "C", "C", "C", "C", "B", "B", "B", "B", "U", "U", "U", "U"][firstChar];
    String dtcFirstNum = (firstChar % 4).toString();
    return "$dtcLetter$dtcFirstNum${hexStr.substring(1, 4)}";
  }

  // ================================================================
  // 6. UI 그리기
  // ================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: Text(widget.device != null ? '차량 진단' : '테스트 모드', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.history), onPressed: _showHistory)],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(40), color: Colors.white,
            child: Column(
              children: [
                Icon(Icons.document_scanner_outlined, size: 80, color: _isScanning ? Colors.blue : Colors.blueGrey),
                const SizedBox(height: 10),
                if (_isScanning) const CircularProgressIndicator()
                else ElevatedButton(
                  onPressed: _startDiagnosis,
                  child: const Text('고장 코드 조회 시작'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _foundDTCs.length,
              itemBuilder: (context, index) {
                var item = _foundDTCs[index];
                return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 36),
                      title: Text(item['code'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Text(item['description'] ?? '알 수 없는 오류'),
                    )
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}