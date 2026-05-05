import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/routes.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final AuthProvider _authProvider;
  late final RouterConfig<Object> _routerConfig;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _routerConfig = AppRoutes.createRouter(_authProvider);
    unawaited(_authProvider.restoreSession());
  }

  @override
  void dispose() {
    _authProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: _authProvider,
      child: MaterialApp.router(
        title: 'Chorus',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        routerConfig: _routerConfig,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
