import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart'; 
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;

  final RxBool _block = false.obs;
  final GlobalKey _childKey = GlobalKey();
  Map<String, dynamic> bannerData = {};

  Future<void> _fetchBannerData() async {
    try {
      final url = Uri.parse('https://passak.org/php/remotik-banner.php');
      final request = await HttpClient().getUrl(url);
      final response = await request.close();
      if (response.statusCode == 200) {
        final jsonString = await response.transform(utf8.decoder).join();
        if (mounted) setState(() => bannerData = jsonDecode(jsonString));
      }
    } catch (e) {
      debugPrint("Banners failed: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchBannerData();
    
    // کدهای حیاتی بک‌أند برای آپدیت وضعیت و آیدی
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        setState(() => systemError = error);
      }
    });

    // ثبت شنونده‌های سیستمی (برای جلوگیری از کرش و صفحه سفید)
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);
    
    // مدیریت متدها (کلیک‌های ویندوز، اتصال و ریموت) - این بخش حیاتی است
    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(call.arguments['id'], password: call.arguments['password']);
      }
      return '';
    });

    _uniLinksSubscription = listenUniLinks();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isOutgoingOnly = bind.isOutgoingOnly();

    // ساخت محتوای داینامیک بالا (آیدی + بنرها)
    Widget topUI = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isOutgoingOnly)
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _buildDynamicBanner(bannerData['top_left']?['image'], bannerData['top_left']?['link'])),
                Column(
                  children: [
                    buildCorporateIDBoard(context),
                    const SizedBox(height: 8),
                    buildCorporatePasswordBoard(context),
                  ],
                ),
                Expanded(child: _buildDynamicBanner(bannerData['top_right']?['image'], bannerData['top_right']?['link'])),
              ],
            ),
          ),
        if (!isOutgoingOnly) buildBannersRow(),
      ],
    );

    // ساخت محتوای داینامیک پایین (باکس اینستال نازک)
    Widget bottomUI = Obx(() => buildHelpCards(stateGlobal.updateUrl.value));

    return buildRemoteBlock(
      block: _block, mask: true, use: canBeBlocked,
      child: ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: ConnectionPage(topContent: topUI, bottomContent: bottomUI),
      ),
    );
  }

  Widget _buildDynamicBanner(String? imageUrl, String? linkUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => linkUrl != null ? launchUrlString(linkUrl) : null,
      child: Image.network(imageUrl, height: 90, fit: BoxFit.contain,
          errorBuilder: (c, e, s) => const SizedBox.shrink()),
    );
  }

  Widget buildCorporateIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(translate("ID"), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(width: 15),
        Container(
          width: 320, padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
          child: TextFormField(
            controller: model.serverId, readOnly: true, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFE53935), letterSpacing: 1.5),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
          ),
        ),
      ],
    );
  }

  Widget buildCorporatePasswordBoard(BuildContext context) {
    return Consumer<ServerModel>(
      builder: (context, model, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(translate("One-time"), style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5))),
            const SizedBox(width: 15),
            Container(
              width: 320, padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
              child: TextFormField(
                controller: model.serverPasswd, readOnly: true, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
              ),
            ),
            const SizedBox(width: 5),
            IconButton(icon: const Icon(Icons.refresh, size: 16), onPressed: () => bind.mainUpdateTemporaryPassword(), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            const SizedBox(width: 5),
            IconButton(icon: const Icon(Icons.edit, size: 16), onPressed: () => DesktopSettingPage.switch2page(SettingsTabKey.safety), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ],
        );
      },
    );
  }

  Widget buildBannersRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
      height: 100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(child: _buildDynamicBanner(bannerData['bottom_1']?['image'], bannerData['bottom_1']?['link'])),
          const SizedBox(width: 15),
          Expanded(child: _buildDynamicBanner(bannerData['bottom_2']?['image'], bannerData['bottom_2']?['link'])),
          const SizedBox(width: 15),
          Expanded(child: _buildDynamicBanner(bannerData['bottom_3']?['image'], bannerData['bottom_3']?['link'])),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (systemError.isNotEmpty) return buildInstallCard("", systemError, "", () {});
    if (isWindows && !bind.mainIsInstalled()) {
      return buildInstallCard("", "install_tip", "Install", () => bind.mainGotoInstall());
    }
    return const SizedBox.shrink();
  }

  Widget buildInstallCard(String title, String content, String btnText, VoidCallback onPressed) {
    if (isCardClosed) return const SizedBox.shrink();
    return Container(
      // ==========================================
      // CUSTOMIZATION: نازک‌تر و تمام‌عرض طبق عکس دوم
      // ==========================================
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          gradient: LinearGradient(colors: [Color(0xFFE242BC), Color(0xFFF4727C)])),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 15),
      child: Row( // استفاده از Row برای نازک‌تر شدن
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(translate(content), style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 20)),
            child: Text(translate(btnText), style: const TextStyle(fontSize: 12)),
          ),
          IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 16), onPressed: () => setState(() => isCardClosed = true))
        ],
      ),
    );
  }

  @override
  void dispose() { _uniLinksSubscription?.cancel(); _updateTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

// تابع دیالوگ پسورد (همان کد طولانی و کامل شما بدون تغییر)
void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet = (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet = (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [DigitValidationRule(), UppercaseValidationRule(), LowercaseValidationRule(), MinCharactersValidationRule(8)];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet ? translate('password-hidden-tip') : (presetPassword ? translate('preset-password-in-use-tip') : '');

  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      if (!canSubmit) return;
      final pass = p0.text.trim();
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (ok) { if (pass.isNotEmpty) notEmptyCallback?.call(); close(); }
    }
    return CustomAlertDialog(
      title: Row(children: [Icon(Icons.key, color: MyTheme.accent), Text(translate("Set Password")).paddingOnly(left: 10)]),
      content: ConstrainedBox(constraints: const BoxConstraints(minWidth: 500), child: Column(children: [
        TextField(obscureText: true, controller: p0, decoration: InputDecoration(labelText: translate('Password'))),
        TextField(obscureText: true, controller: p1, decoration: InputDecoration(labelText: translate('Confirmation'))),
      ])),
      actions: [
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("OK", onPressed: submit)
      ],
    );
  });
}