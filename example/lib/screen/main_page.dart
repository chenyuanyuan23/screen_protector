import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_protector/screen_protector.dart';

class MainPage extends StatefulWidget {
  const MainPage({Key? key}) : super(key: key);

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ScreenProtector.protectDataLeakageWithColor(Colors.orange));
      unawaited(ScreenProtector.preventScreenshotOn());
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Screen Protector'),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              title: const Text('Prevent Screenshot'),
              onTap: () {
                Navigator.pushNamed(context, '/prevent-screenshot');
              },
            ),
            ListTile(
              title: const Text('Protect Screen Data Leakage'),
              onTap: () {
                Navigator.pushNamed(context, '/protect-data-leakage');
              },
            ),
          ],
        ),
      ),
    );
  }
}
