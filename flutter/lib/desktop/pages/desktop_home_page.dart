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
  final _leftPaneScrollController = ScrollController();

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

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isOutgoingOnly = bind.isOutgoingOnly();

    // ========================================================
    // Customization: Remotik Corporate Single-Column Centered UI
    // ========================================================
    return _buildBlock(
      child: ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            key: _childKey,
            children: [
              // 1. آیدی و پسورد شرکتی
              if (!isOutgoingOnly)
                Container(
                  padding: const EdgeInsets.only(top: 30, bottom: 20),
                  child: Column(
                    children: [
                      buildCorporateIDBoard(context),
                      const SizedBox(height: 10),
                      buildCorporatePasswordBoard(context),
                    ],
                  ),
                ),

              // 2. بنرهای داینامیک ۳ تایی
              if (!isOutgoingOnly) buildBannersRow(),

              // 3. نمایش خطاها و هشدار نصب
              Obx(() => buildHelpCards(stateGlobal.updateUrl.value)),

              const Divider(height: 1),

              // 4. بخش کانکت و لیست سیستم‌های اخیر
              Expanded(
                child: ConnectionPage(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  // ==========================================
  // New Methods for Corporate UI
  // ==========================================
  Widget buildCorporateIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            translate("ID"),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 20),
        GestureDetector(
          onDoubleTap: () {
            Clipboard.setData(ClipboardData(text: model.serverId.text));
            showToast(translate("Copied"));
          },
          child: Container(
            width: 350,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: TextFormField(
              controller: model.serverId,
              readOnly: true,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE53935), // رنگ قرمز آیدی
                letterSpacing: 2.0,
              ),
            ).workaroundFreezeLinuxMint(),
          ),
        ),
        const SizedBox(width: 120),
      ],
    );
  }

  Widget buildCorporatePasswordBoard(BuildContext context) {
    return Consumer<ServerModel>(
      builder: (context, model, child) {
        RxBool refreshHover = false.obs;
        RxBool editHover = false.obs;
        final textColor = Theme.of(context).textTheme.titleLarge?.color;
        final showOneTime = model.approveMode != 'click' &&
            model.verificationMethod != kUsePermanentPassword;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 100,
              child: AutoSizeText(
                translate("One-time password"),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12, color: textColor?.withOpacity(0.6)),
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 20),
            GestureDetector(
              onDoubleTap: () {
                if (showOneTime) {
                  Clipboard.setData(ClipboardData(text: model.serverPasswd.text));
                  showToast(translate("Copied"));
                }
              },
              child: Container(
                width: 350,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: TextFormField(
                  controller: model.serverPasswd,
                  readOnly: true,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(fontSize: 16),
                ).workaroundFreezeLinuxMint(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: Row(
                children: [
                  if (showOneTime)
                    AnimatedRotationWidget(
                      onPressed: () => bind.mainUpdateTemporaryPassword(),
                      child: Tooltip(
                        message: translate('Refresh Password'),
                        child: Obx(() => RotatedBox(
                            quarterTurns: 2,
                            child: Icon(
                              Icons.refresh,
                              color: refreshHover.value ? textColor : Colors.grey,
                              size: 20,
                            ))),
                      ),
                      onHover: (value) => refreshHover.value = value,
                    ),
                  const SizedBox(width: 10),
                  if (!bind.isDisableSettings())
                    InkWell(
                      child: Tooltip(
                        message: translate('Change Password'),
                        child: Obx(
                          () => Icon(
                            Icons.edit,
                            color: editHover.value ? textColor : Colors.grey,
                            size: 20,
                          ),
                        ),
                      ),
                      onTap: () => DesktopSettingPage.switch2page(SettingsTabKey.safety),
                      onHover: (value) => editHover.value = value,
                    ),
                ],
              ),
            )
          ],
        );
      },
    );
  }

  Widget buildBannersRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 40),
      height: 140,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: Image.network(
              'https://file.passak.org/upload/u/20260613/passak_logo.png', // لینک عکس اول
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.business, size: 50, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Image.network(
              'https://file.passak.org/upload/u/20260613/test.png', // لینک عکس دوم
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.celebration, size: 50, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Image.network(
              'https://file.passak.org/upload/u/20260613/banner3.png', // لینک عکس سوم
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, size: 50, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Original System & Backend Methods (Untouched)
  // ==========================================

  Widget buildHelpCards(String updateUrl) {
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); 
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    if (isCardClosed) return const SizedBox();

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(40, marginTop, 40, marginTop),
          decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (title.isNotEmpty)
                Text(
                  translate(title),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ).marginOnly(bottom: 6),
              if (content.isNotEmpty)
                Text(
                  translate(content),
                  style: const TextStyle(
                      height: 1.5,
                      color: Colors.white,
                      fontWeight: FontWeight.normal,
                      fontSize: 13),
                ).marginOnly(bottom: 20),
              if (btnText.isNotEmpty)
                FixedWidthButton(
                  width: 150,
                  padding: 8,
                  isOutline: true,
                  text: translate(btnText),
                  textColor: Colors.white,
                  borderColor: Colors.white,
                  textSize: 20,
                  radius: 10,
                  onTap: onPressed,
                )
            ],
          ),
        ),
        if (closeButton == true)
          Positioned(
            top: 25,
            right: 45,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
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
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
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

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }
      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
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
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
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
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
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
                                  : const Color.fromARGB(255, 198, 86, 157)), 
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : const Color.fromARGB(255, 247, 205, 232)); 
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