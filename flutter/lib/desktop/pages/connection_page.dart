import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import '../../common.dart';
import '../../common/formatter/id_formatter.dart'; // این خط اضافه شد
import '../../common/widgets/peer_tab_page.dart';

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
          const Expanded(child: PeerTabPage()),
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
          const Icon(Icons.settings, color: Colors.grey),
          const SizedBox(width: 15),
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0078D7), foregroundColor: Colors.white),
            onPressed: () => connect(context, _idController.id),
            child: Text(translate("Connect")),
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