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
import 'package:url_launcher/url_launcher.dart'; // <--- این خط جا افتاده بود
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size; // <--- این خط جا افتاده بود
import '../widgets/button.dart'; // <--- مقصر اصلی کرش بیلد!

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
  Timer? _updateTimer;
  bool isCardClosed = false;
  
  // اضافه شدن متغیر برای جلوگیری از نوشتن تکراری در رجیستری
  String _lastSavedId = '';

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
    
    // --- اجباری کردن حالت Scale Adaptive به عنوان پیش‌فرض ---
    if (bind.mainGetUserDefaultOption(key: kOptionViewStyle) == '') {
      bind.mainSetUserDefaultOption(key: kOptionViewStyle, value: kRemoteViewStyleAdaptive);
    }
    
    // --- فورس کردن پسورد یکبار مصرف به حالت "فقط عددی" ---
    bind.mainSetOption(key: 'allow-numeric-one-time-password', value: 'Y');
    bind.mainUpdateTemporaryPassword(); // اضافه شد: رفرش درجا برای اطمینان از عددی شدن
    // --------------------------------------------------------

    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      
      // --- قفل امنیتی ضد CLI (هر یک ثانیه سرور Passak فورس می‌شود) ---
      bind.mainSetOption(key: 'custom-rendezvous-server', value: 'passakrd.ir');
      bind.mainSetOption(key: 'custom-relay-server', value: 'passakrd.ir');
      // bind.mainSetOption(key: 'custom-key', value: 'YOUR_KEY'); // در صورت داشتن کلید، این خط را از کامنت درآورید
      // ----------------------------------------------------------------
      
      await gFFI.serverModel.fetchID();
      
      // --- ارسال تمیز و بهینه آیدی به رجیستری ویندوز (برای حسابداری) ---
      String currentId = gFFI.serverModel.serverId.text;
      if (currentId.isNotEmpty && currentId != _lastSavedId && isWindows) {
        _lastSavedId = currentId; // آپدیت متغیر برای جلوگیری از تکرار
        try {
          // مسیر ذخیره: HKEY_CURRENT_USER\Software\Passak
          Process.run('reg', [
            'add',
            'HKCU\\Software\\Passak',
            '/v', 'RemotikID',
            '/t', 'REG_SZ',
            '/d', currentId,
            '/f' // Force overwrite
          ]);
        } catch (e) {
          // اگر ویندوز گیر داد، برنامه کرش نمیکنه و رد میشه
        }
      }
      // ----------------------------------------------------------------

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

    Widget topUI = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isOutgoingOnly)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _buildSimpleBanner(bannerData['top_left'])),
                buildCombinedIDPassCard(context),
                Expanded(child: _buildSimpleBanner(bannerData['top_right'])),
              ],
            ),
          ),
        if (!isOutgoingOnly) buildBannersRow(),
      ],
    );

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

  Widget _buildSimpleBanner(Map<String, dynamic>? data) {
    if (data == null || data['image'] == null || data['image'].toString().isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: () => data['link'] != null ? launchUrlString(data['link']) : null,
      hoverColor: Colors.transparent, splashColor: Colors.transparent, highlightColor: Colors.transparent,
      child: Image.network(data['image'], height: 95, fit: BoxFit.contain, errorBuilder: (c, e, s) => const SizedBox.shrink()),
    );
  }

  // --- ویجت کادر وسط همراه با قابلیت دابل‌کلیک برای کپی آیدی ---
  Widget buildCombinedIDPassCard(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    Color cardColor = isDark ? const Color(0xFF2B2D31) : Colors.white;
    Color boxColor = isDark ? const Color(0xFF1E1F22) : Colors.grey.withOpacity(0.08);
    Color labelColor = isDark ? const Color(0xFFB5BAC1) : Theme.of(context).textTheme.bodySmall!.color!.withOpacity(0.8);
    Color idColor = isDark ? const Color(0xFFFF5252) : const Color(0xFFE53935);
    Color passColor = isDark ? const Color(0xFFE0E0E0) : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black);
    Color borderColor = isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.3);
    Color shadowColor = isDark ? Colors.black.withOpacity(0.5) : Colors.black.withOpacity(0.08);

    return Consumer<ServerModel>(
      builder: (context, model, child) {
        final showOneTime = model.approveMode != 'click' && model.verificationMethod != kUsePermanentPassword;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 25),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: isDark ? Border.all(color: borderColor) : null,
            boxShadow: [
              BoxShadow(color: shadowColor, blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 5)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ردیف ID با قابلیت کپی
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 65, 
                    child: Text(
                      translate("ID"), 
                      textAlign: TextAlign.right, 
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: labelColor)
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onDoubleTap: () {
                      if (model.serverId.text.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: model.serverId.text));
                        showToast(translate("Copied"));
                      }
                    },
                    child: Container(
                      width: 280, padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: cardColor, borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor, width: 1),
                      ),
                      child: TextFormField(
                        controller: model.serverId, readOnly: true, textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: idColor, letterSpacing: 2.0),
                        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                      ),
                    ),
                  ),
                  const SizedBox(width: 77), 
                ],
              ),
              const SizedBox(height: 15),
              // ردیف One-time
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 65,
                    child: Text(
                      translate("One-time"), 
                      textAlign: TextAlign.right, 
                      style: TextStyle(fontSize: 12, color: labelColor)
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 280, padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: boxColor, borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor, width: 1),
                    ),
                    child: TextFormField(
                      controller: model.serverPasswd, readOnly: true, textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, letterSpacing: 1.0, color: passColor),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 67,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        if (showOneTime) 
                          InkWell(
                            onTap: () => bind.mainUpdateTemporaryPassword(),
                            child: Padding(padding: const EdgeInsets.all(4.0), child: Icon(Icons.refresh, size: 18, color: labelColor)),
                          ),
                        const SizedBox(width: 5),
                        InkWell(
                          onTap: () => DesktopSettingPage.switch2page(SettingsTabKey.safety),
                          child: Padding(padding: const EdgeInsets.all(4.0), child: Icon(Icons.edit, size: 18, color: labelColor)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildBannersRow() {
    List<Widget> bannerWidgets = [];
    
    for (int i = 1; i <= 10; i++) {
      String key = 'bottom_$i';
      if (bannerData.containsKey(key) && bannerData[key]?['image'] != null && bannerData[key]['image'].toString().isNotEmpty) {
        bannerWidgets.add(
          DynamicBannerWidget(data: bannerData[key])
        );
      }
    }

    if (bannerWidgets.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 15.0, runSpacing: 15.0,
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
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 2),
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

class DynamicBannerWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  const DynamicBannerWidget({Key? key, required this.data}) : super(key: key);

  @override
  State<DynamicBannerWidget> createState() => _DynamicBannerWidgetState();
}

class _DynamicBannerWidgetState extends State<DynamicBannerWidget> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    String imageUrl = widget.data['image']?.toString() ?? '';
    String linkUrl = widget.data['link']?.toString() ?? '';
    String text = widget.data['text']?.toString() ?? '';
    int mode = int.tryParse(widget.data['overlay_mode']?.toString() ?? '0') ?? 0;

    if (imageUrl.isEmpty) return const SizedBox.shrink();

    bool showOverlay = false;
    bool isFullCover = (mode == 2 || mode == 4);

    if (mode == 1 || mode == 2) {
      showOverlay = true; 
    } else if (mode == 3 || mode == 4) {
      showOverlay = isHovered; 
    }

    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => linkUrl.isNotEmpty ? launchUrlString(linkUrl) : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 140, height: 95, 
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => const SizedBox.shrink()),
                
                if (text.isNotEmpty && mode != 0)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    bottom: showOverlay ? 0 : (isFullCover ? -95 : -35),
                    left: 0, right: 0,
                    height: isFullCover ? 95 : 30,
                    child: Container(
                      alignment: Alignment.center,
                      color: Colors.black.withOpacity(isFullCover ? 0.7 : 0.6),
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
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