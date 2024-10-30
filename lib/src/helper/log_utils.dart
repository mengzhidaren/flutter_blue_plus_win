import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

log(String message){
  print(message);
}

String errorTip(dynamic e){
  if (e is FlutterBluePlusException) {
    return " error:${e.description}";
  } else if (e is PlatformException) {
    return " error:${e.message}";
  }
  return "error:$e";
}

