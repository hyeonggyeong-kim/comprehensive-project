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
  List<String> _foundDTCs = [];

  // 고장 코드 번역 사전
  final Map<String, String> _dtcDictionary = {
    'P0100': '공기 유량 센서(MAF) 회로 이상',
    'P0113': '흡기 온도 센서(IAT) 회로 전압 높음',
    'P0133': '산소 센서 반응 늦음 (Bank 1, Sensor 1)',
    'P0300': '다중 실린더 엔진 실화(Misfire) 감지됨',
    'P0420': '촉매 변환기 정화 효율 저하',
    'P0500': '차속 센서(VSS) 시스템 이상',
    'C0220': 'ABS 휠 속도 센서 이상',
    'U0100': '엔진 제어 모듈(ECM) 통신 끊김',
  };

  // 1. 진단(조회) 시작 함수
  Future<void> _startDiagnosis() async {
    setState(() {
      _isScanning = true;
      _foundDTCs.clear();
    });

    if (widget.device != null) {
      await _readRealDTC(); // 실제 블루투스 통신을 통해 조회만 함
    } else {
      await Future.delayed(const Duration(seconds: 3)); // 시뮬레이션
      setState(() { _foundDTCs = ['P0113', 'P0420']; });
    }

    setState(() => _isScanning = false);

    // 진단 결과 DB 저장
    await _saveResultToDB();
  }

  // 2. 결과 저장
  Future<void> _saveResultToDB() async {
    final prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString('userEmail');
    if (email == null) return;

    final String myIpAddress = '172.30.1.15'; // 핫스팟 IP 적용
    final url = Uri.parse('http://$myIpAddress:8080/api/diagnostics/save');

    try {
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userEmail': email,
          'dtcCodes': _foundDTCs.isEmpty ? '정상' : _foundDTCs.join(','),
          'statusMessage': _foundDTCs.isEmpty ? '차량 상태 정상' : '고장 코드 ${_foundDTCs.length}건 발견'
        }),
      );
    } catch (e) {
      print("저장 실패: $e");
    }
  }

  // 3. 이력 조회 팝업
  void _showHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString('userEmail');
    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }

    final String myIpAddress = '172.30.1.15';
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

  // 4. DTC 조회 로직 (Mode 03 명령만 수행)
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
        StreamSubscription sub = notifyChar.lastValueStream.listen((value) {
          String response = utf8.decode(value, allowMalformed: true).replaceAll(RegExp(r'[\s\r\n>]'), '');
          if (response.startsWith("43") && response.length >= 6) {
            String hexCode = response.substring(2, 6);
            if (hexCode != "0000") {
              // DTC 변환 로직 (Mode 03의 대답을 해석)
              String parsedCode = _parseOBDDTC(hexCode);
              setState(() { if (!_foundDTCs.contains(parsedCode)) _foundDTCs.add(parsedCode); });
            }
          }
        });
        // 03 명령만 전송하여 코드 조회 수행
        await writeChar.write(utf8.encode("03\r"));
        await Future.delayed(const Duration(seconds: 4));
        await sub.cancel();
      }
    } catch (e) { print("진단 에러: $e"); }
  }

  String _parseOBDDTC(String hexStr) {
    if (hexStr.length < 4) return "Unknown";
    int firstChar = int.parse(hexStr[0], radix: 16);
    String dtcLetter = ["P", "P", "P", "P", "C", "C", "C", "C", "B", "B", "B", "B", "U", "U", "U", "U"][firstChar];
    String dtcFirstNum = (firstChar % 4).toString();
    return "$dtcLetter$dtcFirstNum${hexStr.substring(1, 4)}";
  }

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
                String code = _foundDTCs[index];
                return Card(child: ListTile(title: Text(code), subtitle: Text(_dtcDictionary[code] ?? '알 수 없는 코드')));
              },
            ),
          ),
        ],
      ),
    );
  }
}