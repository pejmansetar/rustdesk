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

  // متغیر برای ذخیره اطلاعات بنرها از سمت سرور پاصک
  Map<String, dynamic> bannerData = {};

  // تابعی که JSON را از سرور می‌خواند
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
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isOutgoingOnly = bind.isOutgoingOnly();

    Widget topContent = Column(
      children: [
        if (!isOutgoingOnly)
          Container(
            padding: const EdgeInsets.only(top: 30, bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: _buildDynamicBanner(
                      bannerData['top_left']?['image'],
                      bannerData['top_left']?['link'],
                      height: 100,
                    ),
                  ),
                ),
                Column(
                  children: [
                    buildCorporateIDBoard(context),
                    const SizedBox(height: 10),
                    buildCorporatePasswordBoard(context),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: _buildDynamicBanner(
                      bannerData['top_right']?['image'],
                      bannerData['top_right']?['link'],
                      height: 100,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (!isOutgoingOnly) buildBannersRow(),
      ],
    );

    Widget bottomContent = Obx(() => buildHelpCards(stateGlobal.updateUrl.value));

    return _buildBlock(
      child: ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: ConnectionPage(
            topContent: topContent,
            bottomContent: bottomContent,
          ),
        ),
      ),
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget _buildDynamicBanner(String? imageUrl, String? linkUrl, {double? height}) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return SizedBox(height: height);
    }
    
    return GestureDetector(
      onTap: () {
        if (linkUrl != null && linkUrl.isNotEmpty) {
          launchUrlString(linkUrl);
        }
      },
      child: Image.network(
        imageUrl,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => SizedBox(height: height), 
      ),
    );
  }

  Widget buildCorporateIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 80,
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
                color: Color(0xFFE53935),
                letterSpacing: 2.0,
              ),
            ).workaroundFreezeLinuxMint(),
          ),
        ),
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
              width: 80,
              child: AutoSizeText(
                translate("One-time"),
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
              width: 60,
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
                              size: 18,
                            ))),
                      ),
                      onHover: (value) => refreshHover.value = value,
                    ),
                  const SizedBox(width: 8),
                  if (!bind.isDisableSettings())
                    InkWell(
                      child: Tooltip(
                        message: translate('Change Password'),
                        child: Obx(
                          () => Icon(
                            Icons.edit,
                            color: editHover.value ? textColor : Colors.grey,
                            size: 18,
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
      height: 120,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: _buildDynamicBanner(
              bannerData['bottom_1']?['image'],
              bannerData['bottom_1']?['link'],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _buildDynamicBanner(
              bannerData['bottom_2']?['image'],
              bannerData['bottom_2']?['link'],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _buildDynamicBanner(
              bannerData['bottom_3']?['image'],
              bannerData['bottom_3']?['link'],
            ),
          ),
        ],
      ),
    );
  }

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
      setState(() {
        isCardClosed = true;
      });
    }

    if (isCardClosed) return const SizedBox();

    return Stack(
      children: [
        Container(
          // ==========================================
          // CUSTOMIZATION: نازک‌تر شدن و تمام‌عرض شدن کادر صورتی
          // ==========================================
          margin: const EdgeInsets.fromLTRB(16, 5, 16, 4), // حاشیه‌ها کمتر شد تا به استاتوس بار بچسبد
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), // ضخامت (vertical) کم شد تا نازک‌تر شود
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
                ).marginOnly(bottom: 4),
              if (content.isNotEmpty)
                Text(
                  translate(content),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      height: 1.5,
                      color: Colors.white,
                      fontWeight: FontWeight.normal,
                      fontSize: 13),
                ).marginOnly(bottom: 10), // فاصله با دکمه کمتر شد
              if (btnText.isNotEmpty)
                FixedWidthButton(
                  width: 150,
                  padding: 8,
                  isOutline: true,
                  text: translate(btnText),
                  textColor: Colors.white,
                  borderColor: Colors.white,
                  textSize: 18, // فونت دکمه کمی کوچکتر شد تا در کادر نازک جا شود
                  radius: 8,
                  onTap: onPressed,
                )
            ],
          ),
        ),
        if (closeButton == true)
          Positioned(
            top: 15,
            right: 25,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: closeCard,
            ),
          ),
      ],
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
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