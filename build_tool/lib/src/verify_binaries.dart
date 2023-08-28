import 'dart:io';

import 'package:ed25519_edwards/ed25519_edwards.dart';
import 'package:http/http.dart';

import 'artifacts_provider.dart';
import 'crate_hash.dart';
import 'options.dart';
import 'precompile_binaries.dart';
import 'target.dart';

class VerifyBinaries {
  VerifyBinaries({
    required this.manifestDir,
    required this.libraryName,
  });

  final String manifestDir;
  final String libraryName;

  Future<void> run() async {
    final config = CargokitCrateOptions.load(manifestDir: manifestDir);
    final prebuiltBinaries = config.prebuiltBinaries;
    if (prebuiltBinaries == null) {
      stdout.writeln('Crate does not support prebuilt binaries.');
    } else {
      final crateHash = CrateHash.compute(manifestDir);
      stdout.writeln('Crate hash: $crateHash');

      for (final target in Target.all) {
        final message = 'Checking ${target.rust}...';
        stdout.write(message.padRight(40));
        stdout.flush();

        final artifacts = getArtifactNames(
          target: target,
          libraryName: libraryName,
          remote: true,
        );

        final prefix = prebuiltBinaries.uriPrefix;

        bool ok = true;

        for (final artifact in artifacts) {
          final fileName = PrecompileBinaries.fileName(target, artifact);
          final signatureFileName =
              PrecompileBinaries.signatureFileName(target, artifact);

          final url = Uri.parse('$prefix$crateHash/$fileName');
          final signatureUrl =
              Uri.parse('$prefix$crateHash/$signatureFileName');

          final signature = await get(signatureUrl);
          if (signature.statusCode != 200) {
            stdout.writeln('MISSING');
            ok = false;
            break;
          }
          final asset = await get(url);
          if (asset.statusCode != 200) {
            stdout.writeln('MISSING');
            ok = false;
            break;
          }

          if (!verify(prebuiltBinaries.publicKey, asset.bodyBytes,
              signature.bodyBytes)) {
            stdout.writeln('INVALID SIGNATURE');
            ok = false;
          }
        }

        if (ok) {
          stdout.writeln('OK');
        }
      }
    }
  }
}
