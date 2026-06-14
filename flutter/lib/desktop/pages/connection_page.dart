// main window right pane

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;

class OnlineStatusWidget extends StatefulWidget {
  const OnlineStatusWidget({Key? key, this.onSvcStatusChanged})
      : super(key: key);

  final VoidCallback? onSvcStatusChanged;

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

/// State for the connection page.
class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  final _svcStopped = Get.find<RxBool>(tag: 'stop-service');
  final _svcIsUsingPublicServer = true.obs;
  Timer? _updateTimer;

  double get em => 14.0;
  double? get height => bind.isIncomingOnly() ? null : em * 3;

  void onUsePublicServerGuide() {
    const url = "https://rustdesk.com/pricing";
    canLaunchUrlString(url).then((can) {
      if (can) {
        launchUrlString(url);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(Duration(seconds: 1), () async {
      updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    startServiceWidget() => Offstage(
          offstage: !_svcStopped.value,
          child: InkWell(
                  onTap: () async {
                    await start_service(true);
                  },
                  child: Text(translate("Start service"),
                      style: TextStyle(
                          decoration: TextDecoration.underline, fontSize: em)))
              .marginOnly(left: em),
        );

    setupServerWidget() => Flexible(
          child: Offstage(
            offstage: !(!_svcStopped.value &&
                stateGlobal.svcStatus.value == SvcStatus.ready &&
                _svcIsUsingPublicServer.value),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(', ', style: TextStyle(fontSize: em)),
                Flexible(
                  child: InkWell(
                    onTap: onUsePublicServerGuide,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            translate('setup_server_tip'),
                            style: TextStyle(
                                decoration: TextDecoration.underline,
                                fontSize: em),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        );

    basicWidget() => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: 8,
              width: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _svcStopped.value ||
                        stateGlobal.svcStatus.value == SvcStatus.connecting
                    ? kColorWarn
                    : (stateGlobal.svcStatus.value == SvcStatus.ready
                        ? Color.fromARGB(255, 50, 190, 166)
                        : Color.fromARGB(255, 224, 79, 95)),
              ),
            ).marginSymmetric(horizontal: em),
            Container(
              width: isIncomingOnly ? 226 : null,
              child: _buildConnStatusMsg(),
            ),
            if (!isIncomingOnly) startServiceWidget(),
            if (!isIncomingOnly) setupServerWidget(),
          ],
        );

    return Container(
      height: height,
      child: Obx(() => isIncomingOnly
          ? Column(
              children: [
                basicWidget(),
                Align(
                        child: startServiceWidget(),
                        alignment: Alignment.centerLeft)
                    .marginOnly(top: 2.0, left: 22.0),
              ],
            )
          : basicWidget()),
    ).paddingOnly(right: isIncomingOnly ? 8 : 0);
  }

  _buildConnStatusMsg() {
    widget.onSvcStatusChanged?.call();
    return Text(
      _svcStopped.value
          ? translate("Service is not running")
          : stateGlobal.svcStatus.value == SvcStatus.connecting
              ? translate("connecting_status")
              : stateGlobal.svcStatus.value == SvcStatus.notReady
                  ? translate("not_ready_status")
                  : translate('Ready'),
      style: TextStyle(fontSize: em),
    );
  }

  updateStatus() async {
    final status =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final statusNum = status['status_num'] as int;
    if (statusNum == 0) {
      stateGlobal.svcStatus.value = SvcStatus.connecting;
    } else if (statusNum == -1) {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    } else if (statusNum == 1) {
      stateGlobal.svcStatus.value = SvcStatus.ready;
    } else {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    }
    _svcIsUsingPublicServer.value = await bind.mainIsUsingPublicServer();
    try {
      stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
    } catch (_) {}
  }
}

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage>
    with SingleTickerProviderStateMixin, WindowListener {
  final _idController = IDTextEditingController();
  final RxBool _idInputFocused = false.obs;
  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  String selectedConnectionType = 'Connect';
  bool isWindowMinimized = false;
  final AllPeersLoader _allPeersLoader = AllPeersLoader();
  Iterable<Peer> _autocompleteOpts = [];
  final _menuOpen = false.obs;

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    Get.put<IDTextEditingController>(_idController);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    _idController.dispose();
    windowManager.removeListener(this);
    _allPeersLoader.clear();
    _idFocusNode.removeListener(onFocusChanged);
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (isWindowMinimized && isWindows) {
        Get.forceAppUpdate();
      }
      isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  void onFocusChanged() {
    _idInputFocused.value = _idFocusNode.hasFocus;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }
      final textLength = _idEditingController.value.text.length;
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    
    // ========================================================
    // Customization: Remotik Layout (Top Bar + Expanded History)
    // ========================================================
    return Column(
      children: [
        // 1. Top Navigation / Connect Bar
        _buildTopConnectBar(context),
        
        // 2. History & Recent Sessions (takes remaining space)
        Expanded(
          child: PeerTabPage().paddingSymmetric(horizontal: 12.0),
        ),

        // 3. Status Bar at the bottom
        if (!isOutgoingOnly) const Divider(height: 1),
        if (!isOutgoingOnly) OnlineStatusWidget()
      ],
    );
  }

  void onConnect(
      {bool isFileTransfer = false,
      bool isViewCamera = false,
      bool isTerminal = false}) {
    var id = _idController.id;
    connect(context, id,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal);
  }

  // ========================================================
  // Customization: Horizontal Top Bar for Address Input
  // ========================================================
  Widget _buildTopConnectBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5)),
        )
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Settings Gear Icon (Matches your corporate image)
          Icon(Icons.settings, color: Colors.grey.shade600, size: 24),
          const SizedBox(width: 15),

          // Autocomplete Address Input Field
          Expanded(
            child: RawAutocomplete<Peer>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text == '') {
                  _autocompleteOpts = const Iterable<Peer>.empty();
                } else if (_allPeersLoader.peers.isEmpty &&
                    !_allPeersLoader.isPeersLoaded) {
                  Peer emptyPeer = Peer(
                    id: '', username: '', hostname: '', alias: '', platform: '',
                    tags: [], hash: '', password: '', forceAlwaysRelay: false,
                    rdpPort: '', rdpUsername: '', loginName: '',
                    device_group_name: '', note: '',
                  );
                  _autocompleteOpts = [emptyPeer];
                } else {
                  String textWithoutSpaces =
                      textEditingValue.text.replaceAll(" ", "");
                  if (int.tryParse(textWithoutSpaces) != null) {
                    textEditingValue = TextEditingValue(
                      text: textWithoutSpaces,
                      selection: textEditingValue.selection,
                    );
                  }
                  String textToFind = textEditingValue.text.toLowerCase();
                  _autocompleteOpts = _allPeersLoader.peers
                      .where((peer) =>
                          peer.id.toLowerCase().contains(textToFind) ||
                          peer.username.toLowerCase().contains(textToFind) ||
                          peer.hostname.toLowerCase().contains(textToFind) ||
                          peer.alias.toLowerCase().contains(textToFind))
                      .toList();
                }
                return _autocompleteOpts;
              },
              focusNode: _idFocusNode,
              textEditingController: _idEditingController,
              fieldViewBuilder: (
                BuildContext context,
                TextEditingController fieldTextEditingController,
                FocusNode fieldFocusNode,
                VoidCallback onFieldSubmitted,
              ) {
                updateTextAndPreserveSelection(
                    fieldTextEditingController, _idController.text);
                return Obx(() => Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.withOpacity(0.2))
                  ),
                  child: TextField(
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    focusNode: fieldFocusNode,
                    style: const TextStyle(
                      fontFamily: 'WorkSans',
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    cursorColor: Theme.of(context).textTheme.titleLarge?.color,
                    decoration: InputDecoration(
                        border: InputBorder.none,
                        counterText: '',
                        hintText: _idInputFocused.value
                            ? null
                            : translate('Enter Remote ID'), // Custom hint text
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 10)),
                    controller: fieldTextEditingController,
                    inputFormatters: [IDTextInputFormatter()],
                    onChanged: (v) {
                      _idController.id = v;
                    },
                    onSubmitted: (_) {
                      onConnect();
                    },
                  ).workaroundFreezeLinuxMint(),
                ));
              },
              onSelected: (option) {
                setState(() {
                  _idController.id = option.id;
                  FocusScope.of(context).unfocus();
                });
              },
              optionsViewBuilder: (BuildContext context,
                  AutocompleteOnSelected<Peer> onSelected,
                  Iterable<Peer> options) {
                options = _autocompleteOpts;
                double maxHeight = options.length * 50;
                if (options.length == 1) {
                  maxHeight = 52;
                } else if (options.length == 3) {
                  maxHeight = 146;
                } else if (options.length == 4) {
                  maxHeight = 193;
                }
                maxHeight = maxHeight.clamp(0, 200);

                return Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Material(
                            elevation: 4,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: maxHeight,
                                maxWidth: 319,
                              ),
                              child: _allPeersLoader.peers.isEmpty &&
                                      !_allPeersLoader.isPeersLoaded
                                  ? Container(
                                      height: 80,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ))
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 5),
                                      child: ListView(
                                        children: options
                                            .map((peer) =>
                                                AutocompletePeerTile(
                                                    onSelect: () =>
                                                        onSelected(peer),
                                                    peer: peer))
                                            .toList(),
                                      ),
                                    ),
                            ),
                          ))),
                );
              },
            ),
          ),
          
          const SizedBox(width: 15),

          // Connect Button
          SizedBox(
            height: 40.0,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0078D7), // Windows Blue
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20)
              ),
              onPressed: () {
                onConnect();
              },
              child: Text(translate("Connect"), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 5),

          // Dropdown More options
          Container(
            height: 40.0,
            width: 35.0,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  var offset = Offset(0, 0);
                  return Obx(() => InkWell(
                        child: _menuOpen.value
                            ? Transform.rotate(
                                angle: pi,
                                child: Icon(IconFont.more, size: 16),
                              )
                            : Icon(IconFont.more, size: 16),
                        onTapDown: (e) {
                          offset = e.globalPosition;
                        },
                        onTap: () async {
                          _menuOpen.value = true;
                          final x = offset.dx;
                          final y = offset.dy;
                          await mod_menu
                              .showMenu(
                            context: context,
                            position: RelativeRect.fromLTRB(x, y, x, y),
                            items: [
                              (
                                'Transfer file',
                                () => onConnect(isFileTransfer: true)
                              ),
                              (
                                'View camera',
                                () => onConnect(isViewCamera: true)
                              ),
                              (
                                '${translate('Terminal')} (beta)',
                                () => onConnect(isTerminal: true)
                              ),
                            ]
                                .map((e) => MenuEntryButton<String>(
                                      childBuilder: (TextStyle? style) =>
                                          Text(
                                        translate(e.$1),
                                        style: style,
                                      ),
                                      proc: () => e.$2(),
                                      padding: EdgeInsets.symmetric(
                                          horizontal:
                                              kDesktopMenuPadding.left),
                                      dismissOnClicked: true,
                                    ))
                                .map((e) => e.build(
                                    context,
                                    const MenuConfig(
                                        commonColor: CustomPopupMenuTheme
                                            .commonColor,
                                        height:
                                            CustomPopupMenuTheme.height,
                                        dividerHeight:
                                            CustomPopupMenuTheme
                                                .dividerHeight)))
                                .expand((i) => i)
                                .toList(),
                            elevation: 8,
                          )
                              .then((_) {
                            _menuOpen.value = false;
                          });
                        },
                      ));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}