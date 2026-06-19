import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // 💡 메모장 패키지 임포트
import 'signup.dart';

class LoginDrawer extends StatefulWidget {
  const LoginDrawer({super.key});

  @override
  State<LoginDrawer> createState() => _LoginDrawerState();
}

class _LoginDrawerState extends State<LoginDrawer> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isLoggedIn = false;
  String _userName = '';
  String _carType = '';

  @override
  void initState() {
    super.initState();
    _loadLoginStatus(); // 💡 사이드 메뉴가 열릴 때 기존 로그인 기록이 있는지 확인
  }

  // 💡 스마트폰 메모장에서 로그인 정보 불러오기 함수
  Future<void> _loadLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // 메모장에 'isLoggedIn'이 true로 저장되어 있다면 자동으로 로그인 상태로 만듦
      _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      if (_isLoggedIn) {
        _userName = prefs.getString('userName') ?? '';
        _carType = prefs.getString('carType') ?? '';
      }
    });
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);

    // 🚨 본인 PC의 IPv4 주소인지 확인하세요!
    final String myIpAddress = '172.30.1.99';
    final url = Uri.parse('http://$myIpAddress:8080/api/login');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text,
          'password': _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final name = data['name'] ?? '고객';
        final car = data['carType'] ?? '등록된 차량 없음';

        // 💡 [핵심] 로그인 성공 시 스마트폰 메모장에 로그인 상태와 유저 정보 저장
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('userName', name);
        await prefs.setString('carType', car);
        await prefs.setString('userEmail', _emailController.text);

        setState(() {
          _isLoggedIn = true;
          _userName = name;
          _carType = car;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인 성공!')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이메일이나 비밀번호가 틀렸습니다.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('서버에 연결할 수 없습니다.')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 💡 로그아웃 시 메모장도 깨끗이 비우기
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // 메모장 데이터 전체 삭제

    setState(() {
      _isLoggedIn = false;
      _userName = '';
      _carType = '';
      _emailController.clear();
      _passwordController.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그아웃 되었습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.black),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'MOBYDICK\n사용자 메뉴',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          if (_isLoggedIn)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$_userName님, 환영합니다!', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text('내 차량: $_carType', style: const TextStyle(fontSize: 16, color: Colors.blueGrey)),
                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: _logout,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.black),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('로그아웃', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('로그인', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: '이메일', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '비밀번호', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('로그인', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SignupScreen()),
                        );
                      },
                      child: const Text('아직 계정이 없으신가요? 회원가입', style: TextStyle(color: Colors.blueGrey)),
                    ),
                  )
                ],
              ),
            ),
        ],
      ),
    );
  }
}