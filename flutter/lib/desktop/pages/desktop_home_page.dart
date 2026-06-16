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
import 'package:window_manager/window_manager.dart';

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
            padding: const EdgeInsets.only(top: 20, bottom: 5),
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
    return Consumer<ServerModel>(
      builder: (context, model, child) {
        final showOneTime = model.approveMode != 'click' && model.verificationMethod != kUsePermanentPassword;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 25),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 5)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ردیف ID (کلمه Your حذف شد و دقیقاً شد ID)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(translate("ID"), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 280, padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.withOpacity(0.4), width: 1),
                    ),
                    child: TextFormField(
                      controller: model.serverId, readOnly: true, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFE53935), letterSpacing: 2.0),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                    ),
                  ),
                  const SizedBox(width: 70), 
                ],
              ),
              const SizedBox(height: 15),
              // ردیف One-time
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(translate("One-time"), style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7))),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 280, padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
                    ),
                    child: TextFormField(
                      controller: model.serverPasswd, readOnly: true, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, letterSpacing: 1.0),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 60,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        if (showOneTime) 
                          InkWell(
                            onTap: () => bind.mainUpdateTemporaryPassword(),
                            child: const Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.refresh, size: 18)),
                          ),
                        const SizedBox(width: 5),
                        InkWell(
                          onTap: () => DesktopSettingPage.switch2page(SettingsTabKey.safety),
                          child: const Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.edit, size: 18)),
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
          // برگشت به همون گرادیانت جذاب قبلی
          gradient: LinearGradient(colors: [Color(0xFFE242BC), Color(0xFFF4727C)])),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(translate(content), style: const TextStyle(color: Colors.white, fontSize: 12))),
          // دکمه به حالت آبی استاندارد خودش برگشت
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
    String imageUrl = widget.data['image'] ?? '';
    String linkUrl = widget.data['link'] ?? '';
    String text = widget.data['text'] ?? '';
    int mode = widget.data['overlay_mode'] ?? 0; 

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