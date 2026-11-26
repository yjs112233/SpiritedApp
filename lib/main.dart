import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/http_client.dart';
import 'core/store.dart';
import 'ui/shell.dart';
import 'ui/login/login_page.dart';
import 'ui/cloud/cloud_add_page.dart';
import 'ui/cloud/cloud_files_page.dart';
import 'ui/transfer/transfer_create_page.dart';
import 'ui/transfer/transfer_detail_page.dart';
import 'ui/sync/sync_create_page.dart';
import 'ui/mine/profile_edit_page.dart';
import 'ui/mine/account_page.dart';
import 'ui/order/order_list_page.dart';
import 'ui/gift/gift_list_page.dart';
import 'ui/cloud/oauth_page.dart';
import 'ui/agreement/agreement_page.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppBootstrap());
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  final Future<bool> _init = () async {
    await Store.init();
    return true;
  }();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _init,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        return const SpiritedApp();
      },
    );
  }
}

class SpiritedApp extends StatelessWidget {
  const SpiritedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'QianClouds',
        debugShowCheckedModeBanner: false,
        navigatorKey: ApiClient.navigatorKey,
        theme: AppTheme.light,
        home: const ShellPage(),
        routes: {
          '/login': (_) => const LoginPage(),
          '/cloud/add': (_) => const CloudAddPage(),
          '/cloud/files': (_) => const CloudFilesPage(),
          '/transfer/create': (_) => const TransferCreatePage(),
          '/transfer/detail': (_) => const TransferDetailPage(),
          '/sync/create': (_) => const SyncCreatePage(),
          '/mine/edit': (_) => const ProfileEditPage(),
          '/mine/account': (_) => const AccountPage(),
          '/order/list': (_) => const OrderListPage(),
          '/gift/list': (_) => const GiftListPage(),
          '/oauth': (_) => const OauthPage(),
          '/agreement': (_) => const AgreementPage(),
        },
      ),
    );
  }
}
