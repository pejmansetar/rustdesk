import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import '../../common.dart';
import '../../common/formatter/id_formatter.dart'; 
import '../../common/widgets/peer_tab_page.dart';
// ایمپورت صفحه تنظیمات برای چرخدنده اضافه شد
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildTopConnectBar(context),
          if (widget.topContent != null) widget.topContent!,
          const Divider(height: 1),
          // قرار دادن لیست سیستم‌ها (Sessions) درون Padding برای فاصله داشتن از کناره‌ها
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0), // هم‌تراز با باکس اینستال
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
          // تبدیل آیکون ساده به دکمه تنظیمات (همراه با تغییر کرسر موس)
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            splashRadius: 20,
            tooltip: translate('Settings'),
            onPressed: () => DesktopSettingPage.switch2page(SettingsTabKey.general),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: TextField(
              controller: _idEditingController,
              decoration: InputDecoration(
                hintText: translate('Enter remote ID'),
                fillColor: Colors.grey.withOpacity(0.1),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
              ),
              onChanged: (v) => _idController.id = v,
            ),
          ),
          const SizedBox(width: 15),
          // ساختار دکمه Connect به همراه فلش منوی کشویی (Split-Button)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0078D7), 
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(left: Radius.circular(6)), // لبه گرد فقط برای سمت چپ
                  ),
                ),
                onPressed: () => connect(context, _idController.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text(translate("Connect")),
                ),
              ),
              Container(
                height: 32, // تنظیم ارتفاع برای هم‌اندازه شدن با دکمه اصلی
                decoration: const BoxDecoration(
                  color: Color(0xFF0061AE), // کمی تیره‌تر برای تمایز قسمت فلش
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(6)), // لبه گرد فقط برای سمت راست
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                  ),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
                    tooltip: translate('More Options'),
                    offset: const Offset(0, 36),
                    onSelected: (String result) {
                      if (result == 'file') {
                        connect(context, _idController.id, isFileTransfer: true);
                      } else if (result == 'camera') {
                        connect(context, _idController.id, isViewCamera: true);
                      } else if (result == 'terminal') {
                        connect(context, _idController.id, isTerminal: true);
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'file',
                        child: Text(translate('File Transfer')),
                      ),
                      PopupMenuItem<String>(
                        value: 'camera',
                        child: Text(translate('View Camera')),
                      ),
                      PopupMenuItem<String>(
                        value: 'terminal',
                        child: Text(translate('Terminal (Beta)')),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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