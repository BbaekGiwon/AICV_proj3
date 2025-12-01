import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/splash_screen.dart';

// main 함수를 간결하게 수정
Future<void> main() async {
  // Flutter 앱이 시작되기 전에 필요한 초기화 작업을 수행
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase 서비스 초기화
  await Firebase.initializeApp();

  // 데이터 로딩 로직을 SplashScreen으로 옮기고, 여기서는 바로 앱을 실행
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
      ),
      // 앱의 첫 화면으로 SplashScreen을 지정
      home: const SplashScreen(),
    );
  }
}
