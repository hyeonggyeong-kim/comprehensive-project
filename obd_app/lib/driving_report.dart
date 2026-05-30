import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DrivingReportScreen extends StatefulWidget {
  const DrivingReportScreen({super.key});

  @override
  State<DrivingReportScreen> createState() => _DrivingReportScreenState();
}

class _DrivingReportScreenState extends State<DrivingReportScreen> {
  List<dynamic> _historyList = [];
  bool _isLoading = true;
  final String myIpAddress = '172.30.1.15';

  // 분석 결과
  double _avgScore = 0;
  double _avgSpeed = 0;
  double _avgRpm = 0;
  int _totalTrips = 0;
  int _safeCount = 0;
  int _normalCount = 0;
  int _aggressiveCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchAndAnalyze();
  }

  Future<void> _fetchAndAnalyze() async {
    final prefs = await SharedPreferences.getInstance();
    final String email = prefs.getString('userEmail') ?? 'test@naver.com';
    final url = Uri.parse(
        'http://$myIpAddress:8080/api/driving/history?email=$email');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final list = jsonDecode(utf8.decode(response.bodyBytes));
        _analyze(list);
        setState(() {
          _historyList = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _analyze(List<dynamic> list) {
    if (list.isEmpty) return;

    _totalTrips = list.length;
    double totalScore = 0;
    double totalSpeed = 0;
    double totalRpm = 0;

    for (var r in list) {
      double score = double.tryParse(r['riskScore'].toString()) ?? 0;
      double speed = double.tryParse(r['avgSpeed'].toString()) ?? 0;
      double rpm = double.tryParse(r['avgRpm'].toString()) ?? 0;

      totalScore += score;
      totalSpeed += speed;
      totalRpm += rpm;

      if (score >= 81) {
        _safeCount++;
      } else if (score >= 41) {
        _normalCount++;
      } else {
        _aggressiveCount++;
      }
    }

    _avgScore = totalScore / _totalTrips;
    _avgSpeed = totalSpeed / _totalTrips;
    _avgRpm = totalRpm / _totalTrips;
  }

  // ================================================================
  // 점수 기반 등급 / 색상 / 보험료 감면율 산출
  // ================================================================
  String get _grade {
    if (_avgScore >= 90) return 'S';
    if (_avgScore >= 80) return 'A';
    if (_avgScore >= 70) return 'B';
    if (_avgScore >= 60) return 'C';
    if (_avgScore >= 41) return 'D';
    return 'F';
  }

  Color get _gradeColor {
    switch (_grade) {
      case 'S': return const Color(0xFF00C853);
      case 'A': return const Color(0xFF64DD17);
      case 'B': return const Color(0xFFFFD600);
      case 'C': return const Color(0xFFFF6D00);
      case 'D': return const Color(0xFFDD2C00);
      default:  return const Color(0xFF212121);
    }
  }

  String get _gradeLabel {
    switch (_grade) {
      case 'S': return '최우수 안전 운전자';
      case 'A': return '우수 안전 운전자';
      case 'B': return '양호한 운전자';
      case 'C': return '주의 필요 운전자';
      case 'D': return '개선 필요 운전자';
      default:  return '위험 운전자';
    }
  }

  // 보험료 감면율 (0~15%)
  double get _discountRate {
    if (_avgScore >= 90) return 15.0;
    if (_avgScore >= 80) return 12.0;
    if (_avgScore >= 70) return 8.0;
    if (_avgScore >= 60) return 5.0;
    if (_avgScore >= 41) return 2.0;
    return 0.0;
  }

  // 피드백 목록
  List<Map<String, dynamic>> get _feedbacks {
    final List<Map<String, dynamic>> items = [];

    // 점수 기반
    if (_avgScore >= 81) {
      items.add({
        'icon': Icons.check_circle,
        'color': Colors.green,
        'text': '전반적인 운전 습관이 매우 안전합니다. 현재 수준을 유지하세요.',
      });
    } else if (_avgScore >= 41) {
      items.add({
        'icon': Icons.warning_amber_rounded,
        'color': Colors.orange,
        'text': '운전 습관 개선이 필요합니다. 급가속·급감속을 줄여보세요.',
      });
    } else {
      items.add({
        'icon': Icons.dangerous,
        'color': Colors.red,
        'text': '위험 운전 패턴이 감지됩니다. 안전 운전을 강력히 권고합니다.',
      });
    }

    // 속도 기반
    if (_avgSpeed > 80) {
      items.add({
        'icon': Icons.speed,
        'color': Colors.red,
        'text': '평균 속도(${_avgSpeed.toStringAsFixed(1)}km/h)가 높습니다. 과속을 줄이면 점수가 향상됩니다.',
      });
    } else if (_avgSpeed > 60) {
      items.add({
        'icon': Icons.speed,
        'color': Colors.orange,
        'text': '평균 속도(${_avgSpeed.toStringAsFixed(1)}km/h)가 다소 높습니다. 제한속도를 준수하세요.',
      });
    } else {
      items.add({
        'icon': Icons.speed,
        'color': Colors.green,
        'text': '평균 속도(${_avgSpeed.toStringAsFixed(1)}km/h)가 안전한 수준입니다.',
      });
    }

    // RPM 기반
    if (_avgRpm > 3000) {
      items.add({
        'icon': Icons.settings,
        'color': Colors.red,
        'text': '평균 RPM(${_avgRpm.toStringAsFixed(0)})이 높습니다. 급가속을 줄이면 연비와 점수가 개선됩니다.',
      });
    } else if (_avgRpm > 2000) {
      items.add({
        'icon': Icons.settings,
        'color': Colors.orange,
        'text': '평균 RPM(${_avgRpm.toStringAsFixed(0)})이 다소 높습니다. 부드러운 가속을 권장합니다.',
      });
    } else {
      items.add({
        'icon': Icons.settings,
        'color': Colors.green,
        'text': '평균 RPM(${_avgRpm.toStringAsFixed(0)})이 안정적입니다. 엔진 관리가 잘 되고 있습니다.',
      });
    }

    // 위험 주행 비율
    double aggressiveRatio = _totalTrips > 0
        ? (_aggressiveCount / _totalTrips * 100) : 0;
    if (aggressiveRatio > 30) {
      items.add({
        'icon': Icons.car_crash,
        'color': Colors.red,
        'text': '전체 주행의 ${aggressiveRatio.toStringAsFixed(0)}%가 위험 운전으로 분류됩니다. 주의가 필요합니다.',
      });
    } else if (aggressiveRatio > 10) {
      items.add({
        'icon': Icons.car_crash,
        'color': Colors.orange,
        'text': '전체 주행의 ${aggressiveRatio.toStringAsFixed(0)}%가 위험 운전입니다. 지속적인 개선이 필요합니다.',
      });
    } else {
      items.add({
        'icon': Icons.directions_car,
        'color': Colors.green,
        'text': '위험 운전 비율이 낮습니다. 안전 운전 습관이 잘 형성되어 있습니다.',
      });
    }

    return items;
  }

  // ================================================================
  // build
  // ================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: const Text('성향 리포트',
            style: TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historyList.isEmpty
          ? const Center(
        child: Text(
          '주행 기록이 없습니다.\n주행 후 다시 확인해주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.blueGrey),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── 종합 점수 카드 ──────────────────────────────
            _buildScoreCard(),
            const SizedBox(height: 16),

            // ── 주행 통계 카드 ──────────────────────────────
            _buildStatsCard(),
            const SizedBox(height: 16),

            // ── 보험료 감면 카드 ────────────────────────────
            _buildInsuranceCard(),
            const SizedBox(height: 16),

            // ── 피드백 카드 ─────────────────────────────────
            _buildFeedbackCard(),
            const SizedBox(height: 16),

            // ── 주행 성향 분포 카드 ─────────────────────────
            _buildDistributionCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── 종합 점수 카드 ──────────────────────────────────────────────
  Widget _buildScoreCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [_gradeColor.withOpacity(0.8), _gradeColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Text(
              '종합 운전 점수',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _avgScore.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('점',
                      style: TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '등급 $_grade  |  $_gradeLabel',
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '총 $_totalTrips회 주행 기록 기준',
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }

  // ── 주행 통계 카드 ──────────────────────────────────────────────
  Widget _buildStatsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('주행 통계',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatChip(
                    Icons.directions_car, '총 주행', '$_totalTrips회',
                    Colors.blue),
                _buildStatChip(
                    Icons.speed, '평균 속도',
                    '${_avgSpeed.toStringAsFixed(1)}km/h', Colors.orange),
                _buildStatChip(
                    Icons.settings, '평균 RPM',
                    _avgRpm.toStringAsFixed(0), Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(
      IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          radius: 24,
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── 보험료 감면 카드 ────────────────────────────────────────────
  Widget _buildInsuranceCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      color: const Color(0xFFF0FFF4),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.local_offer, color: Colors.green),
                SizedBox(width: 8),
                Text('보험료 감면 혜택 (UBI 기준)',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('예상 감면율',
                        style:
                        TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(
                      '${_discountRate.toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: _discountRate > 0
                              ? Colors.green
                              : Colors.grey),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildDiscountRow('S등급 (90점~)', '15% 감면'),
                    _buildDiscountRow('A등급 (80~89점)', '12% 감면'),
                    _buildDiscountRow('B등급 (70~79점)', '8% 감면'),
                    _buildDiscountRow('C등급 (60~69점)', '5% 감면'),
                    _buildDiscountRow('D등급 (41~59점)', '2% 감면'),
                    _buildDiscountRow('F등급 (0~40점)', '해당없음',
                        highlight: false),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Text(
                '현재 $_grade등급으로 보험료 최대 ${_discountRate.toStringAsFixed(0)}% 감면 혜택을 받을 수 있습니다.',
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.green,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '※ 실제 보험료 감면율은 보험사 정책에 따라 다를 수 있습니다.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountRow(String grade, String discount,
      {bool highlight = true}) {
    final bool isCurrent = grade.contains(_grade);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          if (isCurrent)
            const Icon(Icons.arrow_right, size: 16, color: Colors.green)
          else
            const SizedBox(width: 16),
          Text(
            '$grade: $discount',
            style: TextStyle(
              fontSize: 11,
              color: isCurrent ? Colors.green : Colors.grey,
              fontWeight:
              isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  // ── 피드백 카드 ─────────────────────────────────────────────────
  Widget _buildFeedbackCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tips_and_updates, color: Colors.amber),
                SizedBox(width: 8),
                Text('맞춤 피드백',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            ..._feedbacks.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(f['icon'] as IconData,
                      color: f['color'] as Color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f['text'] as String,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  // ── 주행 성향 분포 카드 ─────────────────────────────────────────
  Widget _buildDistributionCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('주행 성향 분포',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildDistRow('안전 운전', _safeCount, Colors.green),
            const SizedBox(height: 10),
            _buildDistRow('보통 운전', _normalCount, Colors.orange),
            const SizedBox(height: 10),
            _buildDistRow('위험 운전', _aggressiveCount, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildDistRow(String label, int count, Color color) {
    double ratio =
    _totalTrips > 0 ? count / _totalTrips : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: color)),
            Text('$count회 (${(ratio * 100).toStringAsFixed(0)}%)',
                style: const TextStyle(
                    fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}