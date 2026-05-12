import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:async';

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
      appBar: AppBar(
        leading: const Icon(Icons.menu, color: Colors.black, size: 35),
        title: const Text("MOBYDICK", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true, backgroundColor: Colors.transparent, elevation: 0,
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
                    _showToast("차량진단");
                  }),
                  _buildGridItem(Icons.route_outlined, "주행 기록", () {
                    _showToast("주행 기록");
                  }),
                  _buildGridItem(Icons.thumb_up_alt_outlined, "연비", () {
                    _showToast("연비");
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
class DashboardScreen extends StatefulWidget {
  final BluetoothDevice? device;
  const DashboardScreen({super.key, this.device});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double speed = 0, rpm = 0, coolant = 0, iat = 0, load = 0, map = 0;
  BluetoothCharacteristic? writeChar;
  BluetoothCharacteristic? notifyChar;
  StreamSubscription? _valueSubscription;
  Timer? _timer;
  String _dataBuffer = "";

  @override
  void initState() {
    super.initState();
    if (widget.device != null) { _initRealData(); } else { _initSimulation(); }
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

      _timer = Timer.periodic(const Duration(seconds: 1), (t) => _sendCommands());
    }
  }

  void _sendCommands() async {
    if (writeChar == null) return;
    final pids = ["010C\r", "010D\r", "0105\r", "010F\r", "0104\r", "010B\r"];
    for (var pid in pids) {
      await writeChar!.write(utf8.encode(pid));
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

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
            double val = ((a * 256) + b) / 4;
            if (val < 9000) rpm = val;
          }
        }
        if (cleanData.contains("410D")) {
          int start = cleanData.indexOf("410D") + 4;
          if (cleanData.length >= start + 2) {
            double val = int.parse(cleanData.substring(start, start + 2), radix: 16).toDouble();
            if (val < 300) speed = val;
          }
        }
        if (cleanData.contains("4105")) {
          int start = cleanData.indexOf("4105") + 4;
          if (cleanData.length >= start + 2) {
            coolant = int.parse(cleanData.substring(start, start + 2), radix: 16).toDouble() - 40;
          }
        }
      } catch (e) {
        debugPrint("파싱 에러: $e");
      }
    });
    _dataBuffer = "";
  }

  void _initSimulation() {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      setState(() { speed = 0; rpm = 750 + (t.tick % 50).toDouble(); coolant = 85; });
    });
  }

  @override
  void dispose() { _timer?.cancel(); _valueSubscription?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(title: Text(widget.device != null ? "실시간 주행 데이터" : "테스트 대시보드"), backgroundColor: Colors.white, elevation: 1),
      body: GridView.count(
        padding: const EdgeInsets.all(16), crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16,
        children: [
          _buildCard("속도", speed.toStringAsFixed(0), "km/h"),
          _buildCard("엔진 회전수 (RPM)", rpm.toStringAsFixed(0), "RPM"),
          _buildCard("냉각 온도", coolant.toStringAsFixed(0), "°C"),
          _buildCard("흡기 온도 (IAT)", iat.toStringAsFixed(0), "°C"),
          _buildCard("엔진 부하", load.toStringAsFixed(1), "%"),
          _buildCard("흡기 압력 (MAP)", map.toStringAsFixed(0), "kPa"),
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