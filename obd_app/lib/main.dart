import 'driving_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'login.dart';
import 'diagnostic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'eco_driving_screen.dart';


void main() => runApp(const OBDApp());

class OBDApp extends StatelessWidget {
  const OBDApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MOBYDICK',
      theme: ThemeData(
          scaffoldBackgroundColor: Colors.white,
          primaryColor: Colors.black
      ),
      home: const HomeScreen(),
    );
  }
}

BluetoothDevice? globalConnectedDevice;

// --- 1. 메인 화면 (기획안 image_b9ae41.png 반영) ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const LoginDrawer(),

      appBar: AppBar(
        // 🚨 기존에 있던 leading: Icon(Icons.menu...) 부분은 삭제하세요! (drawer가 자동으로 만들어줍니다)
        iconTheme: const IconThemeData(color: Colors.black, size: 35), // 햄버거 아이콘 색상/크기 지정
        title: const Text("MOBYDICK", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 15),

            // 상단의 빈 라운드 박스 영역
            Container(
              width: double.infinity,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF707070), width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Icon(
                  Icons.directions_car_filled_outlined,
                  size: 75,
                  color: Colors.grey[400],
                ),
              ),
            ),
            const SizedBox(height: 25),

            // 블루투스 연결 버튼 (+ 모양)
            InkWell(
              onTap: () async {
                await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
                final device = await Navigator.push(context, MaterialPageRoute(builder: (context) => const BluetoothScanScreen()));
                if (device != null) setState(() => globalConnectedDevice = device);
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 40, color: globalConnectedDevice != null ? Colors.blue : Colors.black),
                    const SizedBox(width: 15),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            "블루투스 연결",
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: globalConnectedDevice != null ? Colors.blue : Colors.black
                            )
                        ),
                        if (globalConnectedDevice != null)
                          const Text("장치 연결됨", style: TextStyle(color: Colors.blue, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 35),

            // 기획안 기반 6구 그리드 메뉴 리스트 (4열 구성)
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                mainAxisSpacing: 20,
                crossAxisSpacing: 8,
                childAspectRatio: 0.75, // 텍스트 짤림 방지용 종횡비 설정
                children: [
                  _buildGridItem(Icons.speed, "대시보드", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => DashboardScreen(device: globalConnectedDevice)));
                  }),
                  _buildGridItem(Icons.assignment_outlined, "차량진단", () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => DiagnosticScreen(device: globalConnectedDevice))
                    );
                  }),
                  _buildGridItem(Icons.route_outlined, "주행 기록", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const DrivingRecordScreen()));
                  }),
                  _buildGridItem(Icons.thumb_up_alt_outlined, "연비", () {
                    // 기존 _showToast("연비"); 를 지우고 아래 코드로 교체!
                    Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const EcoDrivingScreen())
                    );
                  }),
                  _buildGridItem(Icons.explore_outlined, "운전점수", () {
                    _showToast("운전점수");
                  }),
                  _buildGridItem(Icons.assignment_ind_outlined, "성향리포트", () {
                    _showToast("성향리포트");
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 그리드 전용 아이콘 버튼 빌더
  Widget _buildGridItem(IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 42, color: Colors.black87),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showToast(String menuName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$menuName 기능은 준비 중입니다.")),
    );
  }
}

// --- 2. 블루투스 스캔 화면 (기존 코드와 완벽히 동일) ---
class BluetoothScanScreen extends StatefulWidget {
  const BluetoothScanScreen({super.key});
  @override
  State<BluetoothScanScreen> createState() => _BluetoothScanScreenState();
}

class _BluetoothScanScreenState extends State<BluetoothScanScreen> {
  List<ScanResult> scanResults = [];
  void _startScan() async {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) { if (mounted) setState(() => scanResults = results); });
  }
  @override
  void initState() { super.initState(); _startScan(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("스캐너 선택")),
      body: ListView.builder(
        itemCount: scanResults.length,
        itemBuilder: (context, index) {
          final device = scanResults[index].device;
          return ListTile(
            title: Text(device.platformName.isEmpty ? "Unknown Device" : device.platformName),
            subtitle: Text(device.remoteId.toString()),
            onTap: () async { await device.connect(); Navigator.pop(context, device); },
          );
        },
      ),
    );
  }
}

// --- 3. 통합 대시보드 화면 (기존 코드와 완벽히 동일) ---
// 🟢
// --- 3. 통합 대시보드 화면 (실시간 데이터 수집 및 주행 기록 기능 탑재) ---
class DashboardScreen extends StatefulWidget {
  final BluetoothDevice? device;
  const DashboardScreen({super.key, this.device});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // 💡 [수정됨] 1. 수집할 변수들을 12개로 왕창 늘려줍니다.
  double speed = 0, rpm = 0, coolant = 0, iat = 0, load = 0, map = 0;
  double maf = 0, throttle = 0, fuelLevel = 0, ambient = 0, oilTemp = 0, voltage = 0;

  BluetoothCharacteristic? writeChar;
  BluetoothCharacteristic? notifyChar;
  StreamSubscription? _valueSubscription;
  Timer? _timer;
  String _dataBuffer = "";

  bool _isRecording = false;
  List<Map<String, dynamic>> _drivingLogs = [];
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    if (widget.device != null) { _initRealData(); } else { _initSimulation(); }
  }

  void _toggleRecording() async {
    if (!_isRecording) {
      setState(() {
        _isRecording = true;
        _drivingLogs.clear();
        _startTime = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('주행 데이터 수집을 시작합니다. ⏱️')));
    } else {
      setState(() => _isRecording = false);
      await _sendDrivingRecordToServer();
    }
  }

  Future<void> _sendDrivingRecordToServer() async {
    if (_drivingLogs.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final String email = prefs.getString('userEmail') ?? 'test@naver.com';

    double totalSpeed = 0, totalRpm = 0;
    for (var log in _drivingLogs) {
      totalSpeed += log['speed'];
      totalRpm += log['rpm'];
    }
    double avgSpeed = totalSpeed / _drivingLogs.length;
    double avgRpm = totalRpm / _drivingLogs.length;

    final String myIpAddress = '172.16.38.86'; // 🚨 본인 PC IP 확인
    final url = Uri.parse('http://$myIpAddress:8080/api/driving/save');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userEmail': email,
          'startTime': _startTime.toString().substring(0, 16),
          'endTime': DateTime.now().toString().substring(0, 16),
          'avgSpeed': double.parse(avgSpeed.toStringAsFixed(1)),
          'avgRpm': double.parse(avgRpm.toStringAsFixed(0)),
          'detailedData': jsonEncode(_drivingLogs)
        }),
      );

      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🏎️ 주행 기록(상세 데이터 포함)이 안전하게 저장되었습니다!')));
      }
    } catch (e) {
      print("주행 기록 전송 실패: $e");
    }
  }

  void _initRealData() async {
    List<BluetoothService> services = await widget.device!.discoverServices();
    for (var s in services) {
      for (var c in s.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) writeChar = c;
        if (c.properties.notify || c.properties.indicate) notifyChar = c;
      }
    }

    if (notifyChar != null && writeChar != null) {
      await notifyChar!.setNotifyValue(true);
      _valueSubscription = notifyChar!.lastValueStream.listen((value) { _parseOBDData(value); });

      await writeChar!.write(utf8.encode("ATZ\r"));
      await Future.delayed(const Duration(milliseconds: 500));
      await writeChar!.write(utf8.encode("ATE0\r"));
      await Future.delayed(const Duration(milliseconds: 200));
      await writeChar!.write(utf8.encode("ATS0\r"));
      await Future.delayed(const Duration(milliseconds: 200));

      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        _sendCommands();

        if (_isRecording) {
          // 💡 [수정됨] 3. 장바구니에 새 변수 이름표를 모두 붙여줍니다!
          _drivingLogs.add({
            'timestamp': t.tick,
            'lat': 0.0,
            'lon': 0.0,
            'speed': speed,
            'rpm': rpm,
            'pedal_d': 0.0,
            'throttle': throttle,
            'fuel_rail': 0.0,
            'maf': maf,
            'fuel_level': fuelLevel,
            'torque': 0.0,
            'load': load,
            'map': map,
            'oil_temp': oilTemp,
            'coolant': coolant,
            'stft1': 0.0,
            'stft2': 0.0,
            'ltft1': 0.0,
            'ltft2': 0.0,
            'ambient_temp': ambient,
            'barometric': 0.0,
            'ev_battery': 0.0,
            'dpf_delta': 0.0,
            'dpf_temp': 0.0,
            'iat': iat,
            'egt1': 0.0,
            'egt2': 0.0,
            'module_voltage': voltage,
          });
        }
      });
    }
  }

  void _sendCommands() async {
    if (writeChar == null) return;

    // 💡 [수정됨] 기존 6개에서 -> 전 세계 공통 핵심 센서 12개로 질문 대폭 추가!
    final pids = [
      "010C\r", "010D\r", "0105\r", "010F\r", "0104\r", "010B\r",
      "0110\r", "0111\r", "012F\r", "0146\r", "015C\r", "0142\r"
    ];

    for (var pid in pids) {
      await writeChar!.write(utf8.encode(pid));
      await Future.delayed(const Duration(milliseconds: 70));
    }
  }

  // 💡 [수정됨] 2. 번역기 코드 교체 (12가지를 모두 해석합니다)
  void _parseOBDData(List<int> data) {
    if (data.isEmpty) return;
    String incoming = utf8.decode(data, allowMalformed: true);
    _dataBuffer += incoming;

    if (!_dataBuffer.contains(">")) return;
    String cleanData = _dataBuffer.replaceAll(RegExp(r'[\s\r\n>]'), '').toUpperCase();

    setState(() {
      try {
        if (cleanData.contains("410C")) {
          int start = cleanData.indexOf("410C") + 4;
          if (cleanData.length >= start + 4) {
            int a = int.parse(cleanData.substring(start, start + 2), radix: 16);
            int b = int.parse(cleanData.substring(start + 2, start + 4), radix: 16);
            rpm = ((a * 256) + b) / 4;
          }
        }
        if (cleanData.contains("410D")) {
          int start = cleanData.indexOf("410D") + 4;
          if (cleanData.length >= start + 2) {
            speed = int.parse(cleanData.substring(start, start + 2), radix: 16).toDouble();
          }
        }
        if (cleanData.contains("4105")) {
          int start = cleanData.indexOf("4105") + 4;
          coolant = int.parse(cleanData.substring(start, start + 2), radix: 16).toDouble() - 40;
        }
        if (cleanData.contains("410F")) {
          int start = cleanData.indexOf("410F") + 4;
          iat = int.parse(cleanData.substring(start, start + 2), radix: 16).toDouble() - 40;
        }
        if (cleanData.contains("4104")) {
          int start = cleanData.indexOf("4104") + 4;
          load = int.parse(cleanData.substring(start, start + 2), radix: 16).toDouble() * 100 / 255;
        }
        if (cleanData.contains("410B")) {
          int start = cleanData.indexOf("410B") + 4;
          map = int.parse(cleanData.substring(start, start + 2), radix: 16).toDouble();
        }
        if (cleanData.contains("4110")) {
          int start = cleanData.indexOf("4110") + 4;
          if (cleanData.length >= start + 4) {
            int a = int.parse(cleanData.substring(start, start + 2), radix: 16);
            int b = int.parse(cleanData.substring(start + 2, start + 4), radix: 16);
            maf = ((a * 256) + b) / 100;
          }
        }
        if (cleanData.contains("4111")) {
          int start = cleanData.indexOf("4111") + 4;
          throttle = int.parse(cleanData.substring(start, start + 2), radix: 16).toDouble() * 100 / 255;
        }
        if (cleanData.contains("412F")) {
          int start = cleanData.indexOf("412F") + 4;
          fuelLevel = int.parse(cleanData.substring(start, start + 2), radix: 16).toDouble() * 100 / 255;
        }
        if (cleanData.contains("4146")) {
          int start = cleanData.indexOf("4146") + 4;
          ambient = int.parse(cleanData.substring(start, start + 2), radix: 16).toDouble() - 40;
        }
        if (cleanData.contains("415C")) {
          int start = cleanData.indexOf("415C") + 4;
          oilTemp = int.parse(cleanData.substring(start, start + 2), radix: 16).toDouble() - 40;
        }
        if (cleanData.contains("4142")) {
          int start = cleanData.indexOf("4142") + 4;
          if (cleanData.length >= start + 4) {
            int a = int.parse(cleanData.substring(start, start + 2), radix: 16);
            int b = int.parse(cleanData.substring(start + 2, start + 4), radix: 16);
            voltage = ((a * 256) + b) / 1000;
          }
        }
      } catch (e) {
        debugPrint("파싱 에러: $e");
      }
    });
    _dataBuffer = "";
  }

  void _initSimulation() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        speed = 40 + (t.tick % 30).toDouble();
        rpm = 1500 + (t.tick % 500).toDouble();
        coolant = 85;
        // 시뮬레이션에서도 가짜 데이터를 조금씩 변경해 줍니다.
        throttle = 15 + (t.tick % 10).toDouble();
        maf = 5 + (t.tick % 5).toDouble();
        fuelLevel = 60.5;
        voltage = 13.8;
      });

      if (_isRecording) {
        // 💡 [수정됨] 시뮬레이션용 장바구니에도 새 변수들을 똑같이 적용!
        _drivingLogs.add({
          'timestamp': t.tick,
          'lat': 0.0,
          'lon': 0.0,
          'speed': speed,
          'rpm': rpm,
          'pedal_d': 0.0,
          'throttle': throttle,
          'fuel_rail': 0.0,
          'maf': maf,
          'fuel_level': fuelLevel,
          'torque': 0.0,
          'load': load,
          'map': map,
          'oil_temp': oilTemp,
          'coolant': coolant,
          'stft1': 0.0,
          'stft2': 0.0,
          'ltft1': 0.0,
          'ltft2': 0.0,
          'ambient_temp': ambient,
          'barometric': 0.0,
          'ev_battery': 0.0,
          'dpf_delta': 0.0,
          'dpf_temp': 0.0,
          'iat': iat,
          'egt1': 0.0,
          'egt2': 0.0,
          'module_voltage': voltage,
        });
      }
    });
  }

  @override
  void dispose() { _timer?.cancel(); _valueSubscription?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: Text(widget.device != null ? "실시간 주행 데이터" : "테스트 대시보드"),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.circle, color: _isRecording ? Colors.red : Colors.grey, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      _isRecording ? "주행 데이터 로깅 중... (${_drivingLogs.length}초 쌓임)" : "주행 기록 정지됨",
                      style: TextStyle(fontWeight: FontWeight.bold, color: _isRecording ? Colors.red : Colors.black54),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: _toggleRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: Text(_isRecording ? "주행 종료" : "주행 시작", style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),

          // 💡 실시간 데이터 계기판 그리드 (6개 -> 12개로 확장!)
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(16),
              crossAxisCount: 2, // 2열로 배치
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              // 카드가 12개로 늘어났으므로 비율을 조금 수정해 줍니다.
              childAspectRatio: 1.2,
              children: [
                _buildCard("속도", speed.toStringAsFixed(0), "km/h"),
                _buildCard("엔진 회전수 (RPM)", rpm.toStringAsFixed(0), "RPM"),
                _buildCard("냉각 온도", coolant.toStringAsFixed(0), "°C"),
                _buildCard("흡기 온도 (IAT)", iat.toStringAsFixed(0), "°C"),
                _buildCard("엔진 부하", load.toStringAsFixed(1), "%"),
                _buildCard("흡기 압력 (MAP)", map.toStringAsFixed(0), "kPa"),

                // 👇 새롭게 추가된 6개의 데이터 카드 👇
                _buildCard("공기량 (MAF)", maf.toStringAsFixed(1), "g/s"),
                _buildCard("스로틀 개방도", throttle.toStringAsFixed(1), "%"),
                _buildCard("연료 잔여량", fuelLevel.toStringAsFixed(1), "%"),
                _buildCard("외부 공기 온도", ambient.toStringAsFixed(0), "°C"),
                _buildCard("엔진 오일 온도", oilTemp.toStringAsFixed(0), "°C"),
                _buildCard("배터리 전압", voltage.toStringAsFixed(1), "V"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(String title, String val, String unit) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(val, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          Text(unit, style: const TextStyle(color: Colors.blueGrey, fontSize: 11)),
        ],
      ),
    );
  }
}
