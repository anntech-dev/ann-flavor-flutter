import 'dart:io';
import 'package:ann_flutter_flavor/ann_flutter_flavor.dart';
import 'package:flutter/widgets.dart';
import '../generated/ann_flavor.g.dart';
import '../main.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AnnFlavor.init(
    config: const ProFlavor(),
    platform: Platform.isAndroid
        ? AnnPlatform.android
        : Platform.isIOS
            ? AnnPlatform.ios
            : AnnPlatform.web,
  );

  runApp(const FlavorApp());
}
