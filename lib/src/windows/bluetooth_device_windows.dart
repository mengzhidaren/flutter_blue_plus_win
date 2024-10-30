// Bluetooth Device Page:
// https://github.com/boskokg/flutter_blue_plus/blob/master/lib/src/bluetooth_device.dart

part of 'windows.dart';

class BluetoothDeviceWindows extends BluetoothDevice {
  BluetoothDeviceWindows({
    required this.platformName,
    required super.remoteId,
    this.rssi,
  });
  final tag = "BluetoothDeviceWindows";
  final int? rssi;

  final String platformName;

  // used for 'servicesStream' public api
  final _services = StreamController<List<BluetoothServiceWindows>>.broadcast();

  // late final _connectionStream = WinBle.connectionStreamOf(remoteId.str);

  // used for 'isDiscoveringServices' public api
  final _isDiscoveringServices = _StreamController(initialValue: false);

  // StreamSubscription<bool>? _subscription;

  String get _address => remoteId.str.toLowerCase();

  // stream return whether or not we are currently discovering services
  @Deprecated("planed for removal (Jan 2024). It can be easily implemented yourself") // deprecated on Aug 2023
  Stream<bool> get isDiscoveringServices => _isDiscoveringServices.stream;

  // // Get services
  // //  - returns null if discoverServices() has not been called
  // //  - this is cleared on disconnection. You must call discoverServices() again
  // List<BluetoothService>? get servicesList =>
  //     FlutterBluePlusWindows._knownServices[remoteId];

  /// Get services
  ///  - returns empty if discoverServices() has not been called
  ///    or if your device does not have any services (rare)
  List<BluetoothServiceWindows> get servicesList => FlutterBluePlusWindows._knownServices[remoteId] ?? [];

  /// Stream of bluetooth services offered by the remote device
  ///   - this stream is only updated when you call discoverServices()
  @Deprecated("planed for removal (Jan 2024). It can be easily implemented yourself") // deprecated on Aug 2023
  Stream<List<BluetoothService>> get servicesStream {
    if (FlutterBluePlusWindows._knownServices[remoteId] != null) {
      return _services.stream.newStreamWithInitialValue(
        FlutterBluePlusWindows._knownServices[remoteId]!,
      );
    } else {
      return _services.stream;
    }
  }

  /// Register a subscription to be canceled when the device is disconnected.
  /// This function simplifies cleanup, so you can prevent creating duplicate stream subscriptions.
  ///   - this is an optional convenience function
  ///   - prevents accidentally creating duplicate subscriptions on each reconnection.
  ///   - [next] if true, the the stream will be canceled only on the *next* disconnection.
  ///     This is useful if you setup your subscriptions before you connect.
  ///   - [delayed] Note: This option is only meant for `connectionState` subscriptions.
  ///     When `true`, we cancel after a small delay. This ensures the `connectionState`
  ///     listener receives the `disconnected` event.
  void cancelWhenDisconnected(StreamSubscription subscription, {bool next = false, bool delayed = false}) {
    if (isConnected == false && next == false) {
      subscription.cancel(); // cancel immediately if already disconnected.
    } else if (delayed) {
      FlutterBluePlusWindows._delayedSubscriptions[remoteId] ??= [];
      FlutterBluePlusWindows._delayedSubscriptions[remoteId]!.add(subscription);
    } else {
      FlutterBluePlusWindows._deviceSubscriptions[remoteId] ??= [];
      FlutterBluePlusWindows._deviceSubscriptions[remoteId]!.add(subscription);
    }
  }

  /// Returns true if this device is currently connected to your app
  bool get isConnected {
    return FlutterBluePlusWindows.connectedDevices.contains(this);
  }

  /// Returns true if this device is currently disconnected from your app
  bool get isDisconnected => isConnected == false;
  bool isConnectState = false;
  _checkState(BluetoothConnectionState state) {
    isConnectState = state == BluetoothConnectionState.connected;
    log('$tag $platformName ConnectState $isConnectState');
    if (!isConnectState) {
      log('$tag  _checkState $platformName subscriptions cancel');
      FlutterBluePlusWindows._deviceSubscriptions[remoteId]
          ?.forEach((s) => s.cancel());
      FlutterBluePlusWindows._deviceSubscriptions.remove(remoteId);
    }
  }
  Future<void> connect({
    Duration? timeout = const Duration(seconds: 35), // TODO: implementation missing
    bool autoConnect = false, // TODO: implementation missing
    int? mtu = 512, // TODO: implementation missing
  }) async {
    try {
      await WinBle.connect(_address);
      FlutterBluePlusWindows._deviceSet.add(this);
    } catch (e) {
      log('$tag connect ${errorTip(e)}');
    }
  }

  Future<void> disconnect({
    int androidDelay = 2000, // TODO: implementation missing
    int timeout = 35, // TODO: implementation missing
    bool queue = true, // TODO: implementation missing
  }) async {
    try {
      if(_checkDeviceLive(_address)){
        isConnectState = false;
        await WinBle.disconnect(_address);
      }else{
        log('$tag  disconnect 已经断开连接 _address=$_address');
      }
    } catch (e) {
      log('$tag disconnect ${errorTip(e)}');
    } finally {
      FlutterBluePlusWindows._deviceSet.remove(this);

      FlutterBluePlusWindows._deviceSubscriptions[remoteId]?.forEach((s) => s.cancel());
      FlutterBluePlusWindows._deviceSubscriptions.remove(remoteId);
      // use delayed to update the stream before we cancel it
      Future.delayed(Duration.zero).then((_) {
        FlutterBluePlusWindows._delayedSubscriptions[remoteId]?.forEach((s) => s.cancel());
        FlutterBluePlusWindows._delayedSubscriptions.remove(remoteId);
      });

      FlutterBluePlusWindows._lastChrs[remoteId]?.clear();
      FlutterBluePlusWindows._isNotifying[remoteId]?.clear();
    }
  }
  bool _checkDeviceLive(String addressV){
    return isConnected&&isConnectState;
  }
  Future<List<BluetoothService>> discoverServices({
    bool subscribeToServicesChanged = true, // TODO: implementation missing
    int timeout = 15, // TODO: implementation missing
  }) async {
    if(!_checkDeviceLive(_address)){
      //设备未链接 直接返回
      final cache = FlutterBluePlusWindows._knownServices[remoteId] ?? [];
      log('$tag  discoverServices cache=$cache');
      return cache;
    }
    final listService = <BluetoothServiceWindows>[];

    // List<BluetoothServiceWindows> result = List.from(FlutterBluePlusWindows._knownServices[remoteId] ?? []);
    bool forceR=true;
    try {
      _isDiscoveringServices.add(true);
      final response = await WinBle.discoverServices(_address,forceRefresh: forceR);
      log('$tag  discoverServices response=${response}');
      FlutterBluePlusWindows._characteristicCache[remoteId] ??= <String, List<BluetoothCharacteristic>>{};
      for (final serviceId in response) {
        final characteristic = await WinBle.discoverCharacteristics(
          address: _address,
          serviceId: serviceId,
          forceRefresh: forceR
        );
        final listChar = characteristic
            .map((c) => BluetoothCharacteristicWindows(
          remoteId: remoteId,
          serviceUuid: Guid(serviceId),
          characteristicUuid: Guid(c.uuid),
          descriptors: [],
          // TODO: implementation missing
          propertiesWinBle: c.properties,
        ))
            .toList();
        listService.add(BluetoothServiceWindows(
          remoteId: remoteId,
          serviceUuid: Guid(serviceId),
          // TODO: implementation missing
          isPrimary: true,
          // TODO: implementation missing
          characteristics: listChar,
          // TODO: implementation missing
          includedServices: [],
        ));
        FlutterBluePlusWindows._characteristicCache[remoteId]?[serviceId] =listChar;
      }
      FlutterBluePlusWindows._knownServices[remoteId] = listService;
      _services.add(listService);
    }catch(e){
      log('$tag discoverServices ${errorTip(e)}');
      final cache = FlutterBluePlusWindows._knownServices[remoteId] ?? [];
      if (cache.isNotEmpty) {
        listService.addAll(cache);
      }
    } finally {
      _isDiscoveringServices.add(false);
    }

    return listService;
  }


  DisconnectReason? get disconnectReason {
    // TODO: nothing to do
    return null;
  }

  Stream<BluetoothConnectionState> get connectionState async* {
    await FlutterBluePlusWindows._initialize();
    final map = FlutterBluePlusWindows._connectionStream.latestValue;
    if (map[_address] != null) {
      final state = map[_address]!.isConnected;
      _checkState(state);
      yield state;
    }

    await for (final event in WinBle.connectionStreamOf(_address)) {
      final state = event.isConnected;
      _checkState(state);
      yield state;
    }
    log('$tag Connection State is closed');
  }

  Stream<int> get mtu async* {
    bool isEmitted = false;
    int retryCount = 0;
    while (!isEmitted) {
      if (retryCount > 3) throw "Device not found !";
      try {
        yield await WinBle.getMaxMtuSize(_address);
        isEmitted = true;
      } catch (e) {
        await Future.delayed(const Duration(milliseconds: 500));
        log('$tag mtu ${errorTip(e)}');
      }
    }
  }

  Future<int> readRssi({int timeout = 15}) async {
    return rssi ?? -100;
  }

  Future<int> requestMtu(
    int desiredMtu, {
    double predelay = 0.35,
    int timeout = 15,
  }) async {
    // https://github.com/rohitsangwan01/win_ble/issues/8
    return await WinBle.getMaxMtuSize(_address);
  }

  Future<void> requestConnectionPriority({
    required ConnectionPriority connectionPriorityRequest,
  }) async {
    // TODO: nothing to do
    return;
  }

  /// Set the preferred connection (Android Only)
  ///   - [txPhy] bitwise OR of all allowed phys for Tx, e.g. (Phy.le2m.mask | Phy.leCoded.mask)
  ///   - [txPhy] bitwise OR of all allowed phys for Rx, e.g. (Phy.le2m.mask | Phy.leCoded.mask)
  ///   - [option] preferred coding to use when transmitting on Phy.leCoded
  /// Please note that this is just a recommendation given to the system.
  Future<void> setPreferredPhy({
    required int txPhy,
    required int rxPhy,
    required PhyCoding option,
  }) async {
    // TODO: implementation missing
  }

  Future<void> createBond({
    int timeout = 90, // TODO: implementation missing
  }) async {
    try {
      await WinBle.pair(_address);
    } catch (e) {
      log('$tag createBond ${errorTip(e)}');
    }
  }

  Future<void> removeBond({
    int timeout = 30, // TODO: implementation missing
  }) async {
    try {
      await WinBle.unPair(_address);
    } catch (e) {
      log('$tag removeBond ${errorTip(e)}');
    }
  }

  Future<void> clearGattCache() async {
    // TODO: implementation missing
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BluetoothDevice && runtimeType == other.runtimeType && remoteId == other.remoteId);

  @override
  int get hashCode => remoteId.hashCode;

  @override
  String toString() {
    return 'BluetoothDevice{'
        'remoteId: $remoteId, '
        'platformName: $platformName, '
        'services: ${FlutterBluePlusWindows._knownServices[remoteId]}'
        '}';
  }

  @Deprecated('Use createBond() instead')
  Future<void> pair() async => await createBond();

  @Deprecated('Use remoteId instead')
  DeviceIdentifier get id => remoteId;

  @Deprecated('Use localName instead')
  String get name => localName;

  @Deprecated('Use connectionState instead')
  Stream<BluetoothConnectionState> get state => connectionState;

  @Deprecated('Use servicesStream instead')
  Stream<List<BluetoothService>> get services => servicesStream;
}
