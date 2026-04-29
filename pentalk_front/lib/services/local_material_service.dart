import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/student_session_model.dart';

class LocalMaterialService {
  Future<MaterialModel> importPdf(File sourceFile) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final materialDir = Directory(p.join(documentsDir.path, 'local_materials'));
    if (!await materialDir.exists()) {
      await materialDir.create(recursive: true);
    }

    final originalName = p.basename(sourceFile.path);
    final sanitizedName = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final materialId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final targetPath = p.join(materialDir.path, '${materialId}_$sanitizedName');
    final copiedFile = await sourceFile.copy(targetPath);
    final fileSize = await copiedFile.length();

    return MaterialModel(
      id: materialId,
      title: p.basenameWithoutExtension(originalName),
      fileName: originalName,
      url: copiedFile.path,
      sizeInBytes: fileSize,
      uploadedAt: DateTime.now(),
      type: FileMaterialType.pdf,
    );
  }
}
