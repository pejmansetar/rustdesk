import 'dart:async';
import 'dart:convert'; // ✅ اضافه شد برای jsonDecode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart'; // ← این خط اضافه شد

import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_tab_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';

class ConnectionPage extends StatefulWidget {
  final Widget? topContent;
  final Widget? bottomContent;
  const ConnectionPage({Key? key, this.topContent, this.bottomContent}) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _idController = IDTextEditingController();
  final _idEditingController = TextEditingController();
  
  // ✅ تایمر برای چک وضعیت اتصال به سرور (روش خود RustDesk)
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    Get.put(_idEditingController);
    Get.put(_idController);
    
    // ✅ شروع چک وضعیت اتصال - هر ۱ ثانیه از هسته Rust می‌خواند
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _updateConnectStatus();
    });
    // چک اولیه بلافاصله
    _updateConnectStatus();
  }

  // ✅ آپدیت وضعیت اتصال از هسته Rust
  // این تابع دقیقاً روش خود RustDesk است
  Future<void> _updateConnectStatus() async {
    try {
      final status = jsonDecode(await bind.mainGetConnectStatus())
          as Map<String, dynamic>;
      final statusNum = status['status_num'] as int;
      if (statusNum == 0) {
        // در حال اتصال به سرور
        stateGlobal.svcStatus.value = SvcStatus.connecting;
      } else if (statusNum == -1) {
        // متصل نیست (خطا)
        stateGlobal.svcStatus.value = SvcStatus.notReady;
      } else if (statusNum == 1) {
        // آماده و متصل
        stateGlobal.svcStatus.value = SvcStatus.ready;
      } else {
        stateGlobal.svcStatus.value = SvcStatus.notReady;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  String get _cleanId => _idEditingController.text.trim().replaceAll(' ', '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildTopConnectBar(context),
          
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RichText(
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: 'Remotik ',
                        style: TextStyle(
                          color: Color(0xFF0078D7),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text: 'remote desktop',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (widget.topContent != null) widget.topContent!,
          const Divider(height: 1),
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: const PeerTabPage(),
            ),
          ),
          
          if (widget.bottomContent != null) widget.bottomContent!,
          _buildStatusBar(),
        ],
      ),
    );
  }
  
  Widget _buildTopConnectBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey, size: 26), 
            splashRadius: 22,
            tooltip: translate('Settings'),
            onPressed: () => DesktopSettingPage.switch2page(SettingsTabKey.general),
          ),
          const SizedBox(width: 5),
          
          Expanded(
            child: TextField(
              controller: _idEditingController,
              inputFormatters: [IDTextInputFormatter()], 
              style: const TextStyle(fontSize: 16, letterSpacing: 1.2), 
              decoration: InputDecoration(
                hintText: translate('Enter remote ID'),
                fillColor: Colors.grey.withOpacity(0.1),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
              ),
              onChanged: (v) => _idController.id = v,
              onSubmitted: (_) {
                if (_cleanId.isNotEmpty) {
                  connect(context, _cleanId);
                }
              },
            ).workaroundFreezeLinuxMint(),
          ),
          const SizedBox(width: 15),
            
          Container(
            height: 44, 
            decoration: BoxDecoration(
              color: const Color(0xFF0078D7), 
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
                    hoverColor: Colors.white.withOpacity(0.15),
                    splashColor: Colors.white.withOpacity(0.2),
                    highlightColor: Colors.white.withOpacity(0.1),
                    onTap: () {
                      if (_cleanId.isNotEmpty) {
                        connect(context, _cleanId);
                      }
                    }, 
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18.0),
                      child: Center(
                        child: Text(
                          translate("Connect"), 
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)
                        ),
                      ),
                    ),
                  ),
                ),
                Container(width: 1, color: Colors.white.withOpacity(0.3), height: 28), 
                
                Material(
                  color: Colors.transparent,
                  child: Builder(
                    builder: (buttonContext) => InkWell(
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                      hoverColor: Colors.white.withOpacity(0.15),
                      splashColor: Colors.white.withOpacity(0.2),
                      highlightColor: Colors.white.withOpacity(0.1),
                      onTap: () async {
                        final RenderBox button = buttonContext.findRenderObject() as RenderBox;
                        final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
                        final RelativeRect position = RelativeRect.fromRect(
                          Rect.fromPoints(
                            button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
                            button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                          ),
                          Offset.zero & overlay.size,
                        );

                        final result = await showMenu<String>(
                          context: context,
                          position: position,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          items: [
                            PopupMenuItem<String>(value: 'file', child: Text(translate('File Transfer'))),
                            PopupMenuItem<String>(value: 'camera', child: Text(translate('View Camera'))),
                            PopupMenuItem<String>(value: 'terminal', child: Text(translate('Terminal (Beta)'))),
                          ],
                        );

                        if (result != null) {
                          if (_cleanId.isNotEmpty) {
                            if (result == 'file') {
                              connect(context, _cleanId, isFileTransfer: true);
                            } else if (result == 'camera') {
                              connect(context, _cleanId, isViewCamera: true);
                            } else if (result == 'terminal') {
                              connect(context, _cleanId, isTerminal: true);
                            }
                          }
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Center(
                          child: Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
      
  // ✅ نوار وضعیت پایین - دقیقاً مثل RustDesk اورجینال
  Widget _buildStatusBar() {
    final svcStopped = Get.find<RxBool>(tag: 'stop-service');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: Obx(() {
        // ۱. سرویس متوقفه
        if (svcStopped.value) {
          return Row(
            children: [
              const Icon(Icons.circle, color: Colors.red, size: 10),
              const SizedBox(width: 8),
              Text(
                translate('Service is not running'),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () async {
                  await bind.mainSetOption(
                      key: kOptionStopService, value: '');
                  bind.mainStartService();
                },
                child: Text(
                  translate('Start service'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          );
        }

        // ۲. چک وضعیت اتصال به شبکه (روش دقیق RustDesk)
        final status = stateGlobal.svcStatus.value;

        // در حال اتصال به سرور
        if (status == SvcStatus.connecting) {
          return Row(
            children: [
              const Icon(Icons.circle, color: Colors.orange, size: 10),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  translate('Connecting to Remotik network...'),
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }

        // متصل نیست (خطا در ارتباط)
        if (status == SvcStatus.notReady) {
          return Row(
            children: [
              const Icon(Icons.circle, color: Colors.red, size: 10),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  translate('not_ready_status'),
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }

        // ۳. حالت عادی - آماده و متصل
        return Row(
          children: [
            const Icon(Icons.circle, color: Color(0xFF32BEA6), size: 10),
            const SizedBox(width: 8),
            Text(translate('Ready'), style: const TextStyle(fontSize: 12)),
          ],
        );
      }),
    );
  }
}