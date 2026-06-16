import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import '../../common.dart';
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

  @override
  void initState() {
    super.initState();
    Get.put(_idEditingController);
    Get.put(_idController);
  }

  // تابع کمکی برای گرفتن آیدی تمیز (بدون فاصله)
  String get _cleanId => _idEditingController.text.trim().replaceAll(' ', '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildTopConnectBar(context),
          if (widget.topContent != null) widget.topContent!,
          const Divider(height: 1),
          // بخش لیست سیستم‌ها 
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
          // دکمه چرخ‌دنده
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey, size: 26), // آیکون کمی بزرگتر شد
            splashRadius: 22,
            tooltip: translate('Settings'),
            onPressed: () => DesktopSettingPage.switch2page(SettingsTabKey.general),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: TextField(
              controller: _idEditingController,
              style: const TextStyle(fontSize: 16), // فونت تایپ آیدی کمی بزرگتر شد
              decoration: InputDecoration(
                hintText: translate('Enter remote ID'),
                fillColor: Colors.grey.withOpacity(0.1),
                filled: true,
                // تغییر دوم: اضافه شدن vertical padding برای افزایش ارتفاع باکس
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
              ),
              onChanged: (v) => _idController.id = v,
            ),
          ),
          const SizedBox(width: 15),
          
          // دکمه Connect و منوی کشویی بهینه‌شده
          Container(
            height: 44, // تغییر دوم: ارتفاع دکمه از 36 به 44 افزایش یافت تا هم‌قد باکس متنی شود
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
                    onTap: () {
                      if (_cleanId.isNotEmpty) {
                        connect(context, _cleanId);
                      }
                    }, 
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18.0),
                      child: Center(
                        child: Text(translate("Connect"), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ),
                ),
                Container(width: 1, color: Colors.white.withOpacity(0.3), height: 28), // خط جداکننده هم بلندتر شد
                
                Material(
                  color: Colors.transparent,
                  child: Builder(
                    builder: (buttonContext) => InkWell(
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                      onTap: () async {
                        if (_cleanId.isEmpty) return; 
                        
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
                          if (result == 'file') {
                            connect(context, _cleanId, isFileTransfer: true);
                          } else if (result == 'camera') {
                            connect(context, _cleanId, isViewCamera: true);
                          } else if (result == 'terminal') {
                            connect(context, _cleanId, isTerminal: true);
                          }
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 22),
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
      
  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2)))),
      child: Row(
        children: [
          const Icon(Icons.circle, color: Color(0xFF32BEA6), size: 10),
          const SizedBox(width: 8),
          Text(translate('Ready'), style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}