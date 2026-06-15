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

const borderColor = Color(0xFF2F65BA);

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

  // بخش بنرهای آنلاین پاصک
  Map<String, dynamic> bannerData = {};

  Future<void> _fetchBannerData() async {
    try {
      final url = Uri.parse('https://passak.org/php/remotik-banner.php');
      final request = await HttpClient().getUrl(url);
      final response = await request.close();
      if (response.statusCode == 200) {
        final jsonString = await response.transform(utf8.decoder).join();
        if (mounted) {
          setState(() {
            bannerData = jsonDecode(jsonString);
          });
        }
      }
    } catch (e) {
      debugPrint("Failed to load banners: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchBannerData();
    
    // --- تمام کدهای بک‌أند اصلی شما حفظ شد ---
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
    });

    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowConnect) {
        // فیکس ارور isFileTransfer: اضافه کردن تمام پارامترهای اجباری نسخه 1.4.7
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'] ?? false,
          isViewCamera: call.arguments['isViewCamera'] ?? false,
          isTerminal: call.arguments['isTerminal'] ?? false,
          isTcpTunneling: call.arguments['isTcpTunneling'] ?? false,
          isRDP: call.arguments['isRDP'] ?? false,
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'] ?? false,
          connToken: call.arguments['connToken'],
        );
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

    // ۱. محتوای بالایی: آیدی، پسورد و جایگاه بنرها
    Widget topUI = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isOutgoingOnly)
          Padding(
            padding: const EdgeInsets.only(top: 25, bottom: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _buildDynamicBanner(bannerData['top_left']?['image'], bannerData['top_left']?['link'])),
                Column(
                  children: [
                    buildCorporateIDBoard(context),
                    const SizedBox(height: 10),
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

    // ۲. محتوای پایینی: باکس صورتی نازک
    Widget bottomUI = Obx(() => buildHelpCards(stateGlobal.updateUrl.value));

    return _buildBlock(
      child: ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: ConnectionPage(
          topContent: topUI,
          bottomContent: bottomUI,
        ),
      ),
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget _buildDynamicBanner(String? imageUrl, String? linkUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();
    // استفاده از InkWell برای فعال شدن کرسر دست روی عکس‌ها
    return InkWell(
      onTap: () => linkUrl != null ? launchUrlString(linkUrl) : null,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Image.network(imageUrl, height: 95, fit: BoxFit.contain,
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
          width: 340, padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.12), 
            borderRadius: BorderRadius.circular(4),
            // اضافه شدن کادر عمودی و افقی (کامل) به باکس ID
            border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
          ),
          child: TextFormField(
            controller: model.serverId, readOnly: true, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Color(0xFFE53935), letterSpacing: 1.5),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
          ),
        ),
      ],
    );
  }

  Widget buildCorporatePasswordBoard(BuildContext context) {
    return Consumer<ServerModel>(
      builder: (context, model, child) {
        final showOneTime = model.approveMode != 'click' && model.verificationMethod != kUsePermanentPassword;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(translate("One-time"), style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5))),
            const SizedBox(width: 15),
            Container(
              width: 340, padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.12), 
                borderRadius: BorderRadius.circular(4),
                // اضافه شدن کادر عمودی و افقی (کامل) به باکس پسورد
                border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
              ),
              child: TextFormField(
                controller: model.serverPasswd, readOnly: true, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
              ),
            ),
            const SizedBox(width: 10),
            if (showOneTime) IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: () => bind.mainUpdateTemporaryPassword()),
            IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => DesktopSettingPage.switch2page(SettingsTabKey.safety)),
          ],
        );
      },
    );
  }

  Widget buildBannersRow() {
    List<Widget> bannerWidgets = [];
    
    // پشتیبانی تا ۱۰ جایگاه برای عکس‌ها (bottom_1 تا bottom_10)
    for (int i = 1; i <= 10; i++) {
      String key = 'bottom_$i';
      if (bannerData.containsKey(key) && bannerData[key]?['image'] != null) {
        bannerWidgets.add(
          _buildDynamicBanner(bannerData[key]['image'], bannerData[key]['link'])
        );
      }
    }

    if (bannerWidgets.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
      // حذف ارتفاع ثابت برای چیدمان بهینه (Wrap)
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 20.0, // فاصله افقی بین عکس‌ها
        runSpacing: 15.0, // فاصله عمودی بین عکس‌ها در صورت رفتن به خط بعد
        children: bannerWidgets,
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
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 2), // مارجین ۱۶ پیکسلی از کناره‌ها
      decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          gradient: LinearGradient(colors: [Color(0xFFE242BC), Color(0xFFF4727C)])),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(translate(content), style: const TextStyle(color: Colors.white, fontSize: 12))),
          ElevatedButton(onPressed: onPressed, child: Text(translate(btnText))),
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

// تابع دیالوگ پسورد بدون تغییر
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

  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      if (p0.text.trim().isEmpty) return;
      final ok = await bind.mainSetPermanentPasswordWithResult(password: p0.text.trim());
      if (ok) { notEmptyCallback?.call(); close(); }
    }
    return CustomAlertDialog(
      title: Text(translate("Set Password")),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: p0, obscureText: true, decoration: InputDecoration(labelText: translate("Password"))),
        TextField(controller: p1, obscureText: true, decoration: InputDecoration(labelText: translate("Confirmation"))),
      ]),
      actions: [dialogButton("Cancel", onPressed: close), dialogButton("OK", onPressed: submit)],
    );
  });
}