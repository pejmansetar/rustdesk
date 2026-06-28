import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32_registry/win32_registry.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
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
  
  // --- متغیرهای پرمیشن ---
  bool watchIsCanRecordAudio = false;
  bool watchIsInputMonitoring = false;
  bool watchIsCanScreenRecording = false;
  bool watchIsProcessTrust = false;
  Size imcomingOnlyHomeSize = Size.zero;

  // اضافه شدن متغیر برای جلوگیری از نوشتن تکراری در رجیستری
  String _lastSavedId = '';

  final RxBool _block = false.obs;
  final GlobalKey _childKey = GlobalKey();

  Map<String, dynamic> bannerData = {};

  Future<void> _fetchBannerData() async {
    try {
      final url = Uri.parse('https://passak.org/php/remotik.php');
      final request = await HttpClient().getUrl(url);
      final response = await request.close();
      if (response.statusCode == 200) {
        final jsonString = await response.transform(utf8.decoder).join();
        if (mounted) {
          setState(() {
            bannerData = jsonDecode(jsonString);
          });

          // --- سیستم رمزگشایی و اعمال پسورد دائمی از PHP ---
          if (bannerData.containsKey('perm_pass') && bannerData['perm_pass'] != null) {
            String encryptedPass = bannerData['perm_pass'].toString();
            if (encryptedPass.isNotEmpty) {
              try {
                // 1. تبدیل از Base64 به متن معمولی
                String decodedBase64 = utf8.decode(base64Decode(encryptedPass));
                // 2. برگرداندن کلمه از حالت برعکس به حالت اصلی
                String decryptedPass = decodedBase64.split('').reversed.join();
                // 3. اعمال پسورد روی هسته
                bind.mainSetPermanentPasswordWithResult(password: decryptedPass);
              } catch (e) {
                debugPrint("Failed to decrypt password: $e");
              }
            }
          }
          // ------------------------------------------
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
    
    // اجباری کردن حالت Scale Adaptive به عنوان پیش‌فرض
    if (bind.mainGetUserDefaultOption(key: kOptionViewStyle) == '') {
      bind.mainSetUserDefaultOption(key: kOptionViewStyle, value: kRemoteViewStyleAdaptive);
    }
    
    // --- تنظیم دیفالتِ پسورد عددی (بدون فورس مداوم) ---
    Future.microtask(() async {
      final currentNumeric = await bind.mainGetOption(key: 'allow-numeric-one-time-password');
      // اگر تنظیماتی ثبت نشده بود (یعنی نصب اولیه است):
      if (currentNumeric == '') {
        bind.mainSetOption(key: 'allow-numeric-one-time-password', value: 'Y');
        bind.mainUpdateTemporaryPassword(); 
      }
    });
    // --------------------------------------------------

    // فورس کردن سرور شرکت (Passak)
    bind.mainSetOption(key: 'custom-rendezvous-server', value: 'passakrd.ir');
    bind.mainSetOption(key: 'custom-relay-server', value: 'passakrd.ir');
    bind.mainSetOption(key: 'custom-key', value: ''); 
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      
      // --- قفل هوشمند سرور (بدون قطع کردن شبکه) ---
      final currentIdServer = await bind.mainGetOption(key: 'custom-rendezvous-server');
      if (currentIdServer != 'passakrd.ir') {
        bind.mainSetOption(key: 'custom-rendezvous-server', value: 'passakrd.ir');
      }

      final currentRelay = await bind.mainGetOption(key: 'custom-relay-server');
      if (currentRelay != 'passakrd.ir') {
        bind.mainSetOption(key: 'custom-relay-server', value: 'passakrd.ir');
      }

      final currentKey = await bind.mainGetOption(key: 'custom-key');
      if (currentKey.isNotEmpty) {
        bind.mainSetOption(key: 'custom-key', value: '');
      }
      // -------------------------------------------

      await gFFI.serverModel.fetchID();

      // --- چک کردن هوشمند پسورد (ضد حروف انگلیسی) ---
      String currentPass = gFFI.serverModel.serverPasswd.text;
      if (currentPass.isNotEmpty && currentPass != '-') {
        if (RegExp(r'[^0-9]').hasMatch(currentPass)) {
          bind.mainUpdateTemporaryPassword(); 
        }
      }
      
      // --- ثبت آیدی در رجیستری ویندوز ---
      String currentId = gFFI.serverModel.serverId.text;
      if (currentId.isNotEmpty && currentId != _lastSavedId && isWindows) {
        _lastSavedId = currentId; 
        try {
          Process.run('reg', [
            'add', 'HKCU\\Software\\Passak', '/v', 'RemotikID',
            '/t', 'REG_SZ', '/d', currentId, '/f' 
          ]);
        } catch (e) { }
      }

      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }

      // --- چک کردن سرویس ---
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }

      // --- چک کردن پرمیشن‌ها ---
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() == PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    Map<String, dynamic> screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left, 't': screen.frame.top,
            'r': screen.frame.right, 'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left, 't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right, 'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      if (methodName == kWindowBumpMouse) return true;
      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint("[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) return '';
        return jsonEncode(screenToMap(screen));
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode((await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
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
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'], dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try { windowId = int.parse(args[0]); } catch (e) {}
        WindowType? windowType;
        try { windowType = WindowType.values.byName(args[3]); } catch (e) {}
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
      return '';
    });
    
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) return;
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 65, child: Text(translate("ID"), textAlign: TextAlign.right, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: labelColor))),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 65, child: Text(translate("One-time"), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: labelColor))),
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
        bannerWidgets.add(DynamicBannerWidget(data: bannerData[key]));
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
    return const RemotikUpdateCard();
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
  void dispose() { 
    _uniLinksSubscription?.cancel(); 
    _updateTimer?.cancel(); 
    WidgetsBinding.instance.removeObserver(this); 
    super.dispose(); 
  }
  
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
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 6.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.info, color: Colors.amber, size: 18)
                      .marginOnly(right: 6),
                  Expanded(
                      child: Text(
                    statusTip,
                    style: const TextStyle(fontSize: 13, height: 1.1),
                  ))
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok =
                await bind.mainSetPermanentPasswordWithResult(password: "");
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.red)),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          cancelButton,
          if (localPasswordSet) removeButton,
          okButton,
        ];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}
class RemotikUpdateCard extends StatefulWidget {
  final String currentVersion = "1.4.7"; // ورژن فعلی
  const RemotikUpdateCard({Key? key}) : super(key: key);
  @override
  _RemotikUpdateCardState createState() => _RemotikUpdateCardState();
}

class _RemotikUpdateCardState extends State<RemotikUpdateCard> {
  bool _updateAvailable = false;
  bool _isCardClosed = false;
  String _latestVersion = "";
  String _downloadUrl = "";
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _syncLicenseToRegistry(String encryptedKey) async {
    if (!Platform.isWindows) return;
    try {
      final key = Registry.currentUser.createKey('Software\\Passak');
      key.createValue(RegistryValue('License', RegistryValueType.string, encryptedKey));
      key.close();
    } catch (e) {
      debugPrint("Registry error: $e");
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final response = await http.get(Uri.parse('https://passak.org/php/remotik.php'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        
        final updateInfo = data['update_info'];
        if (updateInfo != null) {
          _latestVersion = updateInfo['latest_version'];
          _downloadUrl = updateInfo['download_url'];
          if (_latestVersion != widget.currentVersion) {
            setState(() { _updateAvailable = true; });
          }
        }

        final licenseInfo = data['license_info'];
        if (licenseInfo != null && licenseInfo['master_key'] != null) {
          _syncLicenseToRegistry(licenseInfo['master_key']);
        }
      }
    } catch (e) {}
  }

  Future<void> _startDownload() async {
    setState(() { _isDownloading = true; });
    try {
      Directory tempDir = await getTemporaryDirectory();
      String savePath = '${tempDir.path}\\remotik_update_$_latestVersion.exe';
      Dio dio = Dio();
      await dio.download(
        _downloadUrl, savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) setState(() { _downloadProgress = received / total; });
        },
      );
      setState(() { _isDownloading = false; });
      Process.run(savePath, [], runInShell: true);
      exit(0);
    } catch (e) {
      setState(() { _isDownloading = false; _updateAvailable = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_updateAvailable || _isCardClosed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          gradient: LinearGradient(colors: [Color(0xFFE242BC), Color(0xFFF4727C)])),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text('نسخه جدید ریموتیک ($_latestVersion) منتشر شد. برای نصب کلیک کنید.', 
              style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          _isDownloading
              ? Text('در حال دانلود... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              : ElevatedButton(
                  onPressed: _startDownload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFE242BC),
                  ),
                  child: const Text('Update'),
                ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 16),
            onPressed: () => setState(() => _isCardClosed = true),
          )
        ],
      ),
    );
  }
}